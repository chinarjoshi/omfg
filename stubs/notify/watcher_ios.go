//go:build ios
// +build ios

package notify

import "errors"

func newWatcher(chan<- EventInfo) watcher {
	return watcherStub{errors.New("notify: not implemented on iOS")}
}
