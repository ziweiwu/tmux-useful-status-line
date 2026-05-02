.PHONY: test lint check

test:
	bats tests/*.bats

lint:
	cd scripts && shellcheck -x *.sh
	shellcheck useful-status-line.tmux

check: lint test
