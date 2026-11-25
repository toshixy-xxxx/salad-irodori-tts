# salad-irodori-tts — Irodori-TTS-Server を Salad で動かすための焼き込みイメージ
#
# 土台は Irodori-TTS-Server 公式 Dockerfile（本ファイル末尾に出典）。
# 公式との差分は次の3点だけ:
#  1. ビルドコンテキストがサーバーリポジトリではないため、ソースを
#     git clone（コミット固定）で取得し、公式の COPY 手順を置き換えた。
#  2. モデル（v4.1-Small 重み + DACVAE コーデック、計 約3.5GB）を
#     HF キャッシュへ焼き込む。Salad のコンテナ内ディスクは揮発し、
#     起動のたびに約3.5GBを落とすのは無駄なため（画像側の教訓）。
#  3. 実行時 env の既定値をイメージに持たせる:
#     IRODORI_HF_CHECKPOINT（未指定だとサーバー既定の旧 v4-Small になるため必須）、
#     HF_HOME（焼き込み先と実行時の参照先を一致させる）、IRODORI_PORT=8088。
# IRODORI_API_KEY はイメージに焼き込まない。Salad 側の環境変数で設定する。

# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=python:3.10-slim
ARG IRODORI_TTS_BACKEND=cu128
# Irodori-TTS-Server の取得コミット（2026-11-26 時点の main 先端で固定）
ARG IRODORI_SERVER_COMMIT=b3c34e13f1c5a0c064bb8922e040c32e26dc6d1d

FROM ${BASE_IMAGE}

ARG IRODORI_TTS_BACKEND
ARG IRODORI_SERVER_COMMIT

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    HF_HOME=/opt/irodori/hf-cache \
    IRODORI_HF_CHECKPOINT=Aratako/Irodori-TTS-v4.1-Small \
    IRODORI_PORT=8088

WORKDIR /app

# 公式 Dockerfile と同じパッケージ構成（clone 用に git は元々含まれる）
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        ffmpeg \
        git \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# --- 差分1: 公式は COPY pyproject.toml uv.lock / README.md LICENSE / src を
# --- コンテキストから行う。ここでは clone で同じ配置を再現する。
RUN git clone https://github.com/Aratako/Irodori-TTS-Server.git /app \
    && git -C /app checkout "${IRODORI_SERVER_COMMIT}" \
    && rm -rf /app/.git

# 公式 Dockerfile の依存解決（2段 sync）をそのまま実行
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv sync --locked --no-dev --no-install-project --extra "${IRODORI_TTS_BACKEND}"

RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv sync --locked --no-dev --no-editable --extra "${IRODORI_TTS_BACKEND}"

# --- 差分2: モデル焼き込み（重み model.safetensors 約3.06GB + コーデック約0.43GB）
# 実行時にサーバーが HF から取得するのと同じ2リポジトリを HF_HOME へ先行取得する。
# コーデックのリポジトリ名はサーバーの IRODORI_CODEC_REPO 既定値と同一。
RUN /app/.venv/bin/python -c "\
from huggingface_hub import snapshot_download; \
snapshot_download('Aratako/Irodori-TTS-v4.1-Small'); \
snapshot_download('Aratako/Semantic-DACVAE-Japanese-32dim'); \
print('models baked into HF_HOME')"

EXPOSE 8088

# 起動コマンドは公式のまま（IRODORI_HOST 既定 0.0.0.0 / IRODORI_PORT 既定 8088）
CMD ["/app/.venv/bin/python", "-m", "irodori_openai_tts"]

# 出典: https://github.com/Aratako/Irodori-TTS-Server/blob/main/Dockerfile
# （2026-11-26 取得、38行。ベース python:3.10-slim、uv sync --extra、
#  EXPOSE 8088、CMD は上記と同一。適応点は冒頭コメントの3点のみ）
