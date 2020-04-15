build:
	swift build
test:
	swift test
all: clean build
run: build
	.build/debug/FlightTest
clean:
	rm -rf .build
	rm -rf Plots
