# syntax=docker/dockerfile:1

#############################
# Stage 1: Install Foundry
#############################
FROM ubuntu:22.04 AS foundry-installer
USER root

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

#############################
# Stage 2: Build the Contracts
#############################
FROM foundry-installer AS builder
WORKDIR /app

# Copy the project files into the container.
COPY . .

# Ensure the cache directory exists and is writable
RUN mkdir -p /app/cache && chmod -R 777 /app/cache

# Install dependencies and compile the contracts.
RUN forge build

#############################
# Stage 3: Runtime Container
#############################
FROM foundry-installer
WORKDIR /app

RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Copy all project files (including built artifacts) from the builder stage.
COPY --from=builder /app /app

# Set the default command to bash.
CMD ["bash"]

ENV FOUNDRY_DISABLE_NIGHTLY_WARNING=1
