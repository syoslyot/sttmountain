# Uploading Expedition Data

這份文件給負責整理出隊資料的幹部使用。資料放進 Google Drive 後，CI 或手動同步流程會把資料整理進 Supabase。

## Solo Expedition

```text
所有出隊資料夾/
  {出隊名稱}/
    {日期}_{名稱}_直企.xlsx
    地圖/
    航跡/
    上繳紀錄/
```

要求：

- 直企檔名必須包含 `直企`。
- `地圖` 可放 pdf、docx、jpg、png、jpeg。
- `航跡` 可放 gpx、kml。
- `上繳紀錄` 可放 txt、md、docx、pdf、Google 文件。

## Group Activity

```text
所有出隊資料夾/
  {活動名稱}/
    {隊伍名稱A}/
      {日期}_{名稱}_直企.xlsx
      地圖/
      航跡/
      上繳紀錄/
    {隊伍名稱B}/
      {日期}_{名稱}_直企.xlsx
      地圖/
      航跡/
      上繳紀錄/
```

每個隊伍資料夾各自需要一份直企。

## Folder Names

子資料夾名稱需精確符合：

```text
地圖
航跡
上繳紀錄
```

名稱不同會導致同步腳本無法分類。

## Sync Window

目前同步只處理 `2026-05-01` 以後建立的資料夾。舊資料若要補入，請先和維護者確認同步策略。

## Common Upload Mistakes

- 直企檔名沒有 `直企`。
- 把 GPX 放進 `地圖`。
- 把上繳紀錄放在隊伍資料夾根目錄。
- 大眾化活動少一層隊伍資料夾。
- Google 文件權限或檔案狀態導致 Service Account 無法讀取。
