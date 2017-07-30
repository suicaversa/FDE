# Facebook Data Extractor(FDE)
- FacebookAPIを使って、過去の投稿ログを取得するツール。  
  あらゆる投稿の本文、投稿日、位置情報、写真リストをjson化して取得。
- 日付で取得範囲を指定する。
- 取得後、json形式でダウンロードが行われる。

## 初期セットアップ
### env設定
- プログラムのルートディレクトリに.envというファイルを作成し、以下の項目の設定が必要。または、同じ環境変数を設定してもOK。
  > SESSION_SECRET= : セッション管理要のランダムな文字列
  > FB_APP_ID= : FacebookAPI利用のためのAPP_ID
  > FB_APP_SECRET= : FacebookAPI利用のためのAPP_SECRET

## 今後対応予定のオプション
- ダウンロードの他に、GoogleSpreadsheetへの転送
- 位置情報をもとに、GoogleMapに投稿をマッピングし、ピンをクリックすると投稿写真と本文が出る機能
