# 推奨: NetlifyにはFlutterビルドをさせず、事前に手元(またはGitHub Actions)で
# `flutter build web --release` を実行し、生成された build/web を
# そのままGitにコミット(または直接アップロード)して静的配信するだけにする。
# → Netlify環境でのFlutter SDKインストール失敗・タイムアウトを回避できる。

[build]
  base = "flutter_app"
  publish = "build/web"
  command = "echo 'build/web is pre-built, nothing to compile'"

# SPAルーティング対応(_redirectsファイルと同じ内容をtomlでも定義可能)
[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200

# --- GitHub Actionsで自動ビルドしたい場合は、Netlify側のcommandは上記のままにして
#     .github/workflows/flutter_web_deploy.yml で `flutter build web` → `netlify deploy`
#     を実行するCI/CDに切り替えるのがより堅牢。
