FROM golang:alpine as builder

RUN apk add --no-cache git

WORKDIR /app/go-sample-app
COPY go.mod .

RUN export GOPROXY="direct"
RUN go env -w GOPRIVATE=*
RUN go mod download

COPY . .
RUN go build -o ./out/go-sample-app main/main.go

FROM golang:alpine

# Set necessary environmet variables needed for our image
RUN apk add --no-cache \
        python3 \
        py3-pip \
        ca-certificates \
    && pip3 install --upgrade pip \
    && pip3 install \
        awscli \
    && rm -rf /var/cache/apk/*

COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy binary from build to main folder
COPY --from=builder /app/go-sample-app/out/go-sample-app /main

# Command to run when starting the container
CMD ["/main"]