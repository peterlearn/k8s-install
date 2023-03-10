GOPATH:=$(shell go env GOPATH)
VERSION=$(shell git describe --tags --always)

.PHONY: build
# build
build:
	go mod tidy
	mkdir -p bin/ && go build -ldflags "-X main.Version=$(VERSION) -X main.Name="give"" -o ./bin/ ./...