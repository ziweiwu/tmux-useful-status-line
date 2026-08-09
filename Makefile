.PHONY: test lint check

test:
	bats tests/*.bats

lint:
	cd scripts && shellcheck -x *.sh
	shellcheck useful-status-line.tmux
	shellcheck -x bin/useful-status
	shellcheck -x tools/make-screenshot.sh

check: lint test
