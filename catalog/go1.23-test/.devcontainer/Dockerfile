# Built by CI and published to
# ghcr.io/strausmann/claude-container-testing/go1.23-test (public package); the
# pushed manifest digest is then pinned into this template's devcontainer.json.
# See .github/workflows/publish-templates.yml.
FROM golang:1.23@sha256:60deed95d3888cc5e4d9ff8a10c54e5edc008c6ae3fba6187be6fb592e19e8c0

# Pinned Go test toolchain, baked into the image itself so it does NOT depend on what's in the
# mounted target repo -- only the target repo's own module deps (its own `go mod download`) stay
# with the target repo. Both versions below were verified against this exact base (go1.23.12,
# confirmed via `go version` inside the built image) before commit: `docker build` succeeds and
# both binaries run (`govulncheck -version` reports `govulncheck@v1.1.3`, `golangci-lint --version`
# reports `v1.61.0 built with go1.23.12`) -- see Task 6 report for the full verification transcript.
RUN go install golang.org/x/vuln/cmd/govulncheck@v1.1.3 \
    && go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.61.0
