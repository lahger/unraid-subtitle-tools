# mkv-autosub: watches a folder of ripped .mkv files, OCRs the chosen Blu-ray/DVD
# subtitle tracks to SRT with Subtitle Edit's command-line tool (seconv), strips
# unwanted audio tracks and remuxes everything into one .mkv with mkvmerge.
FROM ubuntu:24.04

ARG SE_VERSION=v5.3.0
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl jq tini util-linux \
        mkvtoolnix \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-swe \
        tesseract-ocr-dan tesseract-ocr-nor tesseract-ocr-fin \
        hunspell-en-us hunspell-sv \
        libicu74 libfontconfig1 fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/*

# seconv writes helper data next to its binary, so the folder must be writable.
RUN mkdir -p /opt/seconv && \
    curl -fsSL --retry 5 "https://github.com/SubtitleEdit/subtitleedit/releases/download/${SE_VERSION}/SeConv-Linux-x64.tar.gz" \
        | tar xz -C /opt/seconv && \
    chmod -R a+rwX /opt/seconv && \
    ln -s /opt/seconv/seconv /usr/local/bin/seconv

# OCR-fix lists and spell-check dictionaries for seconv's "Fix common OCR errors" pass.
RUN mkdir -p /opt/dictionaries && cd /opt/dictionaries && \
    for f in eng_OCRFixReplaceList.xml swe_OCRFixReplaceList.xml eng_WordSplitList.txt \
             en_US.aff en_US.dic en_US_se.xml en_names.xml names.xml \
             sv_NoBreakAfterList.xml sv_abbreviations.xml; do \
        curl -fsSL --retry 5 -o "$f" "https://raw.githubusercontent.com/SubtitleEdit/subtitleedit/${SE_VERSION}/Dictionaries/$f" || exit 1; \
    done && \
    cp /usr/share/hunspell/sv_SE.aff /usr/share/hunspell/sv_SE.dic . && \
    chmod -R a+rX /opt/dictionaries

COPY autosub.sh /usr/local/bin/autosub.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/autosub.sh /entrypoint.sh

ENV CONFIG_DIR=/config \
    WATCH_DIR=/watch \
    OUTPUT_DIR=/output \
    SUB_LANGS=eng,swe \
    SUB_UNMATCHED=all \
    DETECT_LANGS=eng,swe,dan,nor,fin \
    AUDIO_LANGS=swe \
    DEFAULT_SUB_LANG=eng \
    KEEP_PGS=1 \
    OCR_ENGINE=ollama \
    OCR_FALLBACK=tesseract \
    OLLAMA_URL=http://localhost:11434 \
    OLLAMA_MODEL=qwen2.5vl:7b \
    STABLE_MINUTES=5 \
    SOURCE_AFTER=keep \
    SCAN_INTERVAL=60 \
    OUTPUT_SUFFIX=-REMUX \
    PUID=99 \
    PGID=100 \
    UMASK=000

VOLUME ["/config", "/watch", "/output"]
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
