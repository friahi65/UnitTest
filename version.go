package main

import (
	"fmt"
	"io"
	"runtime"
)

var (
	// Version is a string describing the version of the command
	Version = "dev"
	// BaseName is the name of the program to display as
	BaseName = "basename"
)

// DisplayBuildInfo displays the basename, version and go version used to build.
func DisplayBuildInfo(writer io.Writer) {
	fmt.Fprintf(writer, "%s\n", BaseName)
	fmt.Fprintf(writer, "%s\n", Version)
	fmt.Fprintf(writer, "%s\n", runtime.Version())
}
