build:
	swift build
all: clean build
run: build
	.build/debug/FlightTest
clean:
	rm -rf .build
	rm -rf Plots
