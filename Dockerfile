FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEDEBUG=-all

# ── Base packages ─────────────────────────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine wine32 curl unzip ca-certificates \
        build-essential texinfo libgmp-dev libmpfr-dev libmpc-dev \
        libjansson-dev git wget gnupg2 && \
    rm -rf /var/lib/apt/lists/*

# ── Wine init ─────────────────────────────────────────────────
RUN DISPLAY= timeout 30 wineboot --init 2>/dev/null || true; \
    timeout 10 wineserver -w 2>/dev/null || true

# ── kz release (gru.exe, gzinject.exe, UPS patches) ──────────
RUN curl -sL https://github.com/krimtonz/kz/releases/download/v0.2.1/kz-0.2.1.zip \
        -o /tmp/kz.zip && \
    unzip /tmp/kz.zip -d /opt/kz && \
    rm /tmp/kz.zip

# ── n64 toolchain (mips64-gcc, grc for building kz) ──────────
# Slow on first build (~30-60 min), cached after
RUN git clone https://github.com/glankk/n64.git /tmp/n64-toolchain && \
    cd /tmp/n64-toolchain && \
    ./configure --prefix=/opt/n64 \
        CFLAGS_FOR_TARGET='-mno-check-zero-division' \
        CXX_FLAGS_FOR_TARGET='-mno-check-zero-division' \
        --enable-vc && \
    make && \
    make install && \
    rm -rf /tmp/n64-toolchain

ENV PATH="/opt/n64/bin:$PATH"

# ── gzinject (native, for WAD patching in build+patch mode) ───
RUN git clone https://github.com/krimtonz/gzinject.git /tmp/gzinject && \
    cd /tmp/gzinject && \
    make && \
    cp gzinject /opt/n64/bin/ && \
    rm -rf /tmp/gzinject

# ── devkitPro PPC (for homeboy / VC patches) ──────────────────
RUN wget -q https://apt.devkitpro.org/install-devkitpro-pacman -O /tmp/install-dkp && \
    chmod +x /tmp/install-dkp && \
    /tmp/install-dkp && \
    dkp-pacman -Syu --noconfirm && \
    dkp-pacman -S --noconfirm devkitPPC && \
    rm /tmp/install-dkp

ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITPPC=/opt/devkitpro/devkitPPC
ENV PATH="/opt/devkitpro/devkitPPC/bin:$PATH"

WORKDIR /opt/kz

COPY docker-entrypoint.sh /opt/kz/
RUN chmod +x /opt/kz/docker-entrypoint.sh

ENTRYPOINT ["/opt/kz/docker-entrypoint.sh"]
