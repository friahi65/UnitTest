PACKAGE  ?= $(notdir $(CURDIR))
DOCKERFILE ?= Dockerfile

REGISTRY ?= docker.inca.infoblox.com

VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
			cat $(CURDIR)/.version 2> /dev/null || echo v0)
BRANCH  := $(shell git rev-parse --abbrev-ref HEAD)
COMMIT  := $(shell git rev-parse --short HEAD)

VERSIONSTR := $(VERSION)-$(BRANCH)-$(COMMIT)

BUILDHOST := $(shell hostname -f)

GOPATH   = $(CURDIR)/.gopath~
BIN      = $(GOPATH)/bin
BASE     = $(GOPATH)/src/$(PACKAGE)
PKGS     = $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... | grep -v "^$(PACKAGE)/vendor/"))
TESTPKGS = $(shell env GOPATH=$(GOPATH) $(GO) list -f '{{ if .TestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS))

TESTTIMEOUT = 15

GO      = go
GODOC   = godoc
GOFMT   = gofmt
GLIDE   = glide
SHASUM  = shasum
DOCKER  = docker

GOARCH  ?= $(shell go env GOARCH | tr A-Z a-z)
GOOS  ?= $(shell go env GOOS | tr A-Z a-z)


VERBOSE ?= 0
Q = $(if $(filter 1,$(VERBOSE)),,@)
M = $(shell printf "\033[34;1m▶\033[0m")

SED = sed
AWK = awk

.PHONY: all
all: fmt lint vendor | $(BASE) ; $(info $(M) building executable…) @ ## Build program binary
	$Q cd $(BASE) && GOARCH=$(GOARCH) GOOS=$(GOOS) $(GO) build \
		-tags release \
		-ldflags '-X main.Version=$(VERSIONSTR) -X main.BaseName=$(PACKAGE)' \
		-o bin/$(PACKAGE) main.go version.go

$(BASE): ; $(info $(M) setting GOPATH…)
	$Q mkdir -p $(dir $@)
	$Q ln -sf $(CURDIR) $@
	$Q ln -sf $(BASE) $(dir $(BASE))/basecode

	$(info $(M) Update package in glide.yaml file)
	$Q $(SED) -i.bak "s,^package:.*,package: $(PACKAGE)," glide.yaml
	@touch glide.yaml
	@rm glide.yaml.bak

# Tools

GOLINT = $(BIN)/golint
$(BIN)/golint: | $(BASE) ; $(info $(M) building golint…)
	$Q go get github.com/golang/lint/golint

GOCOVMERGE = $(BIN)/gocovmerge
$(BIN)/gocovmerge: | $(BASE) ; $(info $(M) building gocovmerge…)
	$Q go get github.com/wadey/gocovmerge

GOCOV = $(BIN)/gocov
$(BIN)/gocov: | $(BASE) ; $(info $(M) building gocov…)
	$Q go get github.com/axw/gocov/...

GOCOVXML = $(BIN)/gocov-xml
$(BIN)/gocov-xml: | $(BASE) ; $(info $(M) building gocov-xml…)
	$Q go get github.com/AlekSi/gocov-xml

GO2XUNIT = $(BIN)/go2xunit
$(BIN)/go2xunit: | $(BASE) ; $(info $(M) building go2xunit…)
	$Q go get github.com/tebeka/go2xunit

# Tests

TEST_TARGETS := test-default test-bench test-short test-verbose test-race
.PHONY: $(TEST_TARGETS) test-xml tests
test-bench:   ARGS=-run=__absolutelynothing__ -bench=. ## Run benchmarks
test-short:   ARGS=-short        ## Run only short tests
test-verbose: ARGS=-v            ## Run tests in verbose mode with coverage reporting
test-race:    ARGS=-race         ## Run tests with race detector
$(TEST_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_TARGETS): test
tests: fmt lint vendor | $(BASE) ; $(info $(M) running $(NAME:%=% )tests…) @ ## Run tests
	$Q cd $(BASE) && $(GO) test -timeout $(TESTTIMEOUT)s $(ARGS) $(TESTPKGS)

test-xml: fmt lint vendor | $(BASE) $(GO2XUNIT) ; $(info $(M) running $(NAME:%=% )tests…) @ ## Run tests with xUnit output
	$Q cd $(BASE) && 2>&1 $(GO) test -timeout 20s -v $(TESTPKGS) | tee test/tests.output
	$(GO2XUNIT) -fail -input test/tests.output -output test/tests.xml

COVERAGE_MODE = atomic
COVERAGE_PROFILE = $(COVERAGE_DIR)/profile.out
COVERAGE_XML = $(COVERAGE_DIR)/coverage.xml
COVERAGE_HTML = $(COVERAGE_DIR)/index.html
.PHONY: test-coverage test-coverage-tools
test-coverage-tools: | $(GOCOVMERGE) $(GOCOV) $(GOCOVXML)
test-coverage: COVERAGE_DIR := $(CURDIR)/test/coverage.$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
test-coverage: fmt lint vendor test-coverage-tools | $(BASE) ; $(info $(M) running coverage tests…) @ ## Run coverage tests
	$Q mkdir -p $(COVERAGE_DIR)/coverage
	$Q cd $(BASE) && for pkg in $(TESTPKGS); do \
		$(GO) test \
			-coverpkg=$$($(GO) list -f '{{ join .Deps "\n" }}' $$pkg | \
					grep '^$(PACKAGE)/' | grep -v '^$(PACKAGE)/vendor/' | \
					tr '\n' ',')$$pkg \
			-covermode=$(COVERAGE_MODE) \
			-coverprofile="$(COVERAGE_DIR)/coverage/`echo $$pkg | tr "/" "-"`.cover" $$pkg ;\
	 done
	$Q $(GOCOVMERGE) $(COVERAGE_DIR)/coverage/*.cover > $(COVERAGE_PROFILE)
	$Q $(GO) tool cover -html=$(COVERAGE_PROFILE) -o $(COVERAGE_HTML)
	$Q $(GOCOV) convert $(COVERAGE_PROFILE) | $(GOCOVXML) > $(COVERAGE_XML)

.PHONY: lint
lint: vendor | $(BASE) $(GOLINT) ; $(info $(M) running golint…) @ ## Run golint
	$Q cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GOLINT) $$pkg | tee /dev/stderr)" || ret=1 ; \
	 done ; exit $$ret

.PHONY: fmt
fmt: ; $(info $(M) running gofmt…) @ ## Run gofmt on all source files
	@ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/); do \
		$(GOFMT) -l -w $$d/*.go || ret=$$? ; \
	 done ; exit $$ret

# Dependency management

glide.lock: glide.yaml | $(BASE) ; $(info $(M) updating dependencies…)
	$Q cd $(BASE) && $(GLIDE) update
	@touch $@

vendor: glide.lock | $(BASE) ; $(info $(M) retrieving dependencies…) ## Setup vendor code
	$Q cd $(BASE) && $(GLIDE) --quiet install
	@ln -sf . vendor/src
	@touch $@

# Misc

.PHONY: clean
clean: 	## Cleanup everything
	$(info $(M) cleaning…)
	@rm -rf $(GOPATH)
	@rm -rf bin
	@rm -rf test/tests.* test/coverage.*

.PHONY: help
help:  ## Display help
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		$(AWK) 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}' | sort

.PHONY: version
version:	## Display version on the output
	@echo $(VERSIONSTR)

.PHONY: package
package:	## Display package name
	@echo $(PACKAGE)

.PHONY: docker 
docker: $(DOCKERFILE) all  ## Build docker image
	$(info $(M) Building docker image for $(GOOS) $(GOARCH))
	@$(eval PACKAGESHA := $(shell $(SHASUM) bin/$(PACKAGE) | $(AWK) '{print $$1}' ))
	@$(DOCKER) build --build-arg binary="$(PACKAGE)" \
	   				--build-arg version="$(VERSIONSTR)" \
					--build-arg arch="$(GOARCH)" \
					--build-arg os="$(GOOS)" \
					--build-arg sha256="$(PACKAGESHA)" \
					--build-arg buildhost="$(BUILDHOST)" \
					-t $(REGISTRY)/$(PACKAGE):$(VERSION) .

.PHONY: release
release: docker ; @ ## Push docker image to repository
ifneq "$(GOOS)" "linux"
	$(warning Building docker imager for OS $(GOOS) !)
endif
	@echo "Not implemented yet"
	@$(DOCKER) push $(REGISTRY)/$(PACKAGE):$(VERSION)
	@$(DOCKER) rmi -f $(REGISTRY)/$(PACKAGE):$(VERSION)


