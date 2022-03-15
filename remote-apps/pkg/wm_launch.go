package remote_apps

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
)

const WM_LAUNCH_SOLIB = "/var/run/appconfig/.remote-apps-launcher/wm-launch-preload.so"

func findLibX11xcb() (string, error) {
	resp := ""

	cmd := exec.Command("ldconfig", "-p")
	stdoutStderr, err := cmd.CombinedOutput()
	if err != nil {
		return resp, fmt.Errorf("failed to find lib: %s, %v", string(stdoutStderr), err)
	}

	scanner := bufio.NewScanner(bytes.NewReader(stdoutStderr))
	scanner.Split(bufio.ScanLines)

	libRE := regexp.MustCompile("libX11-xcb.so.1 .* => (.*)")

	for scanner.Scan() {
		line := scanner.Text()
		matches := libRE.FindStringSubmatch(line)
		if len(matches) > 0 {
			resp = matches[1]
			break
		}
	}
	if len(resp) == 0 {
		return resp, fmt.Errorf("libX11-xcb.so.1 library not found")
	}

	return resp, nil
}

func findWmLaunchLib() (string, error) {
	resp := ""

	if _, err := os.Stat(WM_LAUNCH_SOLIB); errors.Is(err, os.ErrNotExist) {
		return resp, fmt.Errorf("wm-launch lib not found at %s:", WM_LAUNCH_SOLIB)
	}
	resp = WM_LAUNCH_SOLIB
	return resp, nil
}

func GetWMLaunchPreloadString() (string, error) {
	resp := ""

	xcbLib, err := findLibX11xcb()
	if err != nil {
		return resp, err
	}

	wmLaunchLib, err := findWmLaunchLib()
	if err != nil {
		return resp, err
	}
	resp = fmt.Sprintf("%s:%s", xcbLib, wmLaunchLib)

	return resp, nil
}
