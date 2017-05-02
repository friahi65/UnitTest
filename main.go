/* Copyright 2017 Infoblox, Inc
 *
 * Package main is just an entry point.
 * No application code should be written in this file or package.
 *
 * All application code should live under cmd or another package
 * to be imported below.
 *
 * Note that due to the build system implemented in the makefile,
 * any package must be imported as a child of "basecode/" as shown
 * below for the cmd package.
 */

package main

import (
	"os"

	"basecode/cmd"
)

func main() {
	// currently displays the version unconditionally.
	// TODO: add support for standard command line arguments/parameter passing
	// as part of the template.
	DisplayBuildInfo(os.Stdout)

	// do not write code here, add application code in cmd.Main()
	cmd.Main()
}
