name: Numbers3 過去データ自動取り込み

# 毎日 22:30 JST (13:30 UTC) に実行。抽せん結果反映後の時間帯を想定。
# 手動実行(workflow_dispatch)もできるようにしておく。
on:
  schedule:
    - cron: "30 13 * * *"
  workflow_dispatch:

jobs:
  collect:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: 依存パッケージインストール
        run: pip install -r requirements.txt

      - name: 過去データ取り込み実行
        env:
          # Settings > Secrets and variables > Actions で登録した接続文字列を使用
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: python -m app.collector
