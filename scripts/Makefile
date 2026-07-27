.PHONY: build run test clean wire swag migrate-up migrate-down lint

# Build
build:
	go build -o bin/meowtv ./cmd/server

# Run
run:
	go run ./cmd/server

# Test
test:
	go test -v ./...

# Clean
clean:
	rm -rf bin/

# Wire dependency injection
wire:
	cd internal/wire && wire

# Swagger documentation
swag:
	swag init -g cmd/server/main.go -o docs

# Database migration
migrate-up:
	migrate -path migrations -database "sqlite://$(shell pwd)/data/meowtv.db" up

migrate-down:
	migrate -path migrations -database "sqlite://$(shell pwd)/data/meowtv.db" down

# Lint
lint:
	golangci-lint run ./...

# Download dependencies
deps:
	go mod download
	go mod tidy