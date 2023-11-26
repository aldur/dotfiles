FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
    && apt-get install --no-install-recommends -y curl ca-certificates xz-utils sudo procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -rm -d /home/aldur -s /bin/bash -g root -G sudo -u 1001 aldur \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER aldur
WORKDIR /home/aldur

RUN curl -LO https://nixos.org/nix/install \
    && sh install --yes --daemon \
    && rm -rf install

# RUN git clone https://github.com/aldur/dotfiles .dotfiles

ENV USER aldur
ENV DEBIAN_FRONTEND teletype

ENTRYPOINT ["/bin/bash", "-c", "sudo /nix/var/nix/profiles/default/bin/nix-daemon"]
