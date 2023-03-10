FROM golang:1.17 AS builder

WORKDIR /src
#COPY proto proto
COPY main.go main.go
COPY go.mod go.mod
#RUN go mod init server

WORKDIR /src

RUN git config --global url."https://oauth2:glpat-iehtnh3GhsW-4Gp3eAyo@gitlab.com".insteadOf "https://gitlab.com"
# RUN go env -w GOPRIVATE=gitlab.com
RUN GOPROXY=https://goproxy.cn go build -o main

FROM debian:stable-slim

RUN chmod 777 /tmp && apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates  \
        netbase \
        && rm -rf /var/lib/apt/lists/ \
        && apt-get autoremove -y && apt-get autoclean -y

COPY --from=builder /src/ /app

WORKDIR /app

CMD ["./main"]
