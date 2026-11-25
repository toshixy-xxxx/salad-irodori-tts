# salad-irodori-tts

Irodori-TTS-Server（OpenAI TTS API 互換サーバー）を SaladCloud で動かすための
カスタムコンテナイメージのリポジトリ。

- 土台：[Aratako/Irodori-TTS-Server](https://github.com/Aratako/Irodori-TTS-Server)
  公式 Dockerfile（コミット `b3c34e1` に固定）
- 焼き込み済み：モデル `Aratako/Irodori-TTS-v4.1-Small`（重み約3.06GB）と
  コーデック `Aratako/Semantic-DACVAE-Japanese-32dim`（約0.43GB）
- 待ち受けポート：8088（`GET /health`、`POST /v1/audio/speech`）
- イメージ名：`ghcr.io/<GitHubユーザー名>/salad-irodori-tts:latest`（Public）
- 秘密情報はイメージに含めない。`IRODORI_API_KEY` は Salad 側の環境変数で設定する

## 1. リポジトリを作って push する（ユーザー作業）

1. GitHub で新規リポジトリを作成する
   - 名前は任意（推奨：`salad-irodori-tts`。イメージ名はワークフロー側で
     固定されているため、リポジトリ名と一致しなくてもよい）
   - **Public** を選ぶ
   - README 等の初期ファイルは作らない（空リポジトリ）
2. このフォルダの中身をそのまま push する

```bash
cd <このフォルダ>
git init
git add .
git commit -m "Irodori-TTS server image for Salad"
git branch -M main
git remote add origin https://github.com/<GitHubユーザー名>/<リポジトリ名>.git
git push -u origin main
```

## 2. GitHub Actions がすること

- `main` への push（または Actions 画面からの手動実行 `workflow_dispatch`）で起動
- Dockerfile をビルドし、`ghcr.io/<GitHubユーザー名>/salad-irodori-tts:latest`
  として GHCR へ push する（`GITHUB_TOKEN` の `packages: write` 権限を使用。
  追加のシークレット登録は不要）
- ビルドは GitHub 側で完結する。Salad 側の課金は発生しない
  （画像側の実績：イメージプルは Salad の課金対象外区間）

Actions タブでワークフローが緑（成功）になったことを確認する。

## 3. GHCR イメージが Public で pull できることを確認する

初回 publish 直後はパッケージが Private のままの場合がある。その場合は：

1. GitHub のプロフィール → **Packages** → `salad-irodori-tts` を開く
2. **Package settings** → Danger Zone の **Change visibility** → **Public** に変更

匿名 pull の検証（ログインしていない状態で 200 が返れば公開済み）：

```bash
OWNER=<GitHubユーザー名>
TOKEN=$(curl -s "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/salad-irodori-tts:pull" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  https://ghcr.io/v2/${OWNER}/salad-irodori-tts/manifests/latest
# 200 = 無認証で pull 可能（画像側で同じ手順で検証済み）
```

## 4. イメージができたら Salad での次の手順

コンテナグループの設定正本は、Muse 側の準備パッケージにある：

- `~/workspace/eroge/voice_prep_2026-11-26/container/container_group.json`

そこへ今回のイメージを当てはめる際の要点：

- `container.image` を `ghcr.io/<GitHubユーザー名>/salad-irodori-tts:latest` に差し替える
- 環境変数：`IRODORI_PORT=8088`、`IRODORI_HF_CHECKPOINT=Aratako/Irodori-TTS-v4.1-Small`
  （イメージ側にも既定値として入っているが、グループ側でも明示する）
- `IRODORI_API_KEY` は**Salad 側の環境変数でのみ**設定する（このリポジトリや
  イメージに値を入れない）
- networking：http / 認証 ON / ポート 8088
- 起動後、ゲートウェイ経由で `GET /health` が返ることを確認してから生成に入る
- **使い終わったら必ずコンテナグループを Stop する**（止め忘れが唯一の無駄課金経路）
