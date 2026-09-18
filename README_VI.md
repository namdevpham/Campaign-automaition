# Ethopex Workspace V1.4 — Fanpage Batch Selector

## Fanpage batch

Campaign Automation có thêm:

- `Fanpage` dropdown
- `Làm mới Pages`

Tool tải danh sách page LIVE từ Ethopex:

`GET /api/v1/my-asset-groups/fb-pages`

Danh sách hiển thị:

`internal_id · Page Name · external_id`

## Chạy hàng loạt

Chọn một Fanpage rồi tick nhiều record.

Tất cả Campaign trong lần chạy dùng cùng page đó.

## ID mapping theo setcamp.har

EthoPex dùng 2 ID khác nhau:

- Campaign top-level `facebook_page_id` = Facebook `external_id`
- Ad `facebook_page_id` = Ethopex page asset `id`

Tool map tự động cả hai.

## Fanpage fallback

Nếu chưa tải được live API, mặc định vẫn là:

The Quiz Library
- internal id: 1295446
- external id: 119394474601402

## Đổi page

Nếu một record đã có Campaign và bạn đổi Fanpage:

- Content giữ nguyên
- Creative giữ nguyên
- local Campaign/Ad Set/Ad state cũ được reset
- tool tạo Campaign mới cho page mới

Nếu page không đổi, vẫn chống tạo trùng Campaign.

## Full flow

TEST PIPELINE
→ CHẠY FULL
→ Content
→ Creative
→ Campaign
→ Ad Set
→ Ad


---

# V1.5 — Bulk Quiz Import

## Một nút import toàn bộ dữ liệu

Data Manager có nút:

`Import Folder Hàng Loạt`

Chọn một folder cha chứa nhiều quiz folder.

Ví dụ:

```text
BATCH/
├── WORLD CAPITALS QUIZ/
│   ├── WORLD CAPITALS QUIZ.jpg
│   ├── WORLD CAPITALS QUIZ.json
│   └── WORLD CAPITALS QUIZ.html
├── MOVIE QUIZ/
│   ├── MOVIE QUIZ.png
│   ├── MOVIE QUIZ.json
│   └── MOVIE QUIZ.html
└── ...
```

Tool quét đệ quy toàn bộ folder.

## Mapping

- basename → Name
- Image → Image
- JSON.primaryTexts[0] → Primary Text
- JSON.headlines[0] → Headline
- JSON.descriptions[0] → Description
- HTML → Source View

## Validate Source View

Trước khi import, HTML chạy qua chính `SourceViewParser`
của Campaign Automation.

Nếu không đọc được question pool thì record bị bỏ qua và báo lỗi.

## Chống duplicate

Nếu Data Manager đã có record cùng Name:

- không tạo record trùng;
- cập nhật Image + Ads Content + Source View vào record cũ;
- giữ STT/createdAt của record cũ.

Record mới được thêm tiếp theo STT n+1.

## Tối ưu

- scan / parse / copy file chạy background;
- UI không bị khóa trong lúc đọc nhiều folder;
- records.json chỉ persist một lần sau cả batch;
- __MACOSX và hidden files tự bỏ qua.

## Image hỗ trợ

- JPG
- JPEG
- PNG
- WEBP


---

# V1.6 — Shared Content + Creative Variants + Update Version

## Rule khóa mới

Tool deduplicate ở cấp **Source / Content**, không deduplicate ở cấp Creative.

Ví dụ 3 bộ creative cùng Source name:

```text
WORLD CAPITALS QUIZ
├── Creative A
├── Creative B
└── Creative C
```

Sau import:

```text
1 Source View
→ 1 Content
   ├── CT1_WORLD CAPITALS QUIZ → Campaign 1
   ├── CT2_WORLD CAPITALS QUIZ → Campaign 2
   └── CT3_WORLD CAPITALS QUIZ → Campaign 3
```

`TEST PIPELINE` / Gemini / QA chỉ chạy một lần cho Content group.

`CREATE CONTENT` chỉ gọi Ethopex Content API một lần.

`content_id` được share cho mọi Creative variant.

Mỗi Creative vẫn:
- upload image riêng;
- có Ads Content riêng;
- có creative_id riêng;
- có campaign_id / ad_set_id / ad_id riêng.

## Re-import

Creative được fingerprint bằng Image + Primary Text + Headline + Description.

Re-import cùng bộ:
- không nhân đôi Creative record.

Creative mới cùng Source:
- được thêm thành CT tiếp theo.

## UPDATE VERSION

Header app có nút:

`UPDATE VERSION`

V1.6 là bản full cuối cùng bạn cần cài trước để có updater.

Từ các version sau, ChatGPT có thể gửi ZIP patch nhỏ.
Chọn ZIP đó bằng `UPDATE VERSION`, app sẽ:
- kiểm tra version;
- backup source;
- apply update;
- tự đóng;
- tự chạy build.command;
- mở version mới.

Xem `UPDATE_PACKAGE_FORMAT.md`.


---

# V1.6.1 — Multi-Folder Bulk Import

`Import Folder Hàng Loạt` bây giờ cho phép chọn NHIỀU folder trực tiếp trong Finder.

Cách chọn:
- Command + click: chọn nhiều folder rời nhau.
- Shift + click: chọn một dải folder.
- Có thể chọn một folder cha như trước; tool vẫn quét đệ quy.

Tool sẽ quét toàn bộ folder đã chọn trong cùng một batch.

Nếu người dùng vô tình chọn cả folder cha và folder con:
- cùng một Creative fingerprint chỉ được import một lần;
- không nhân đôi dữ liệu do vùng scan chồng nhau.

Rule Source/Creative giữ nguyên:
- Source name trùng → 1 Content.
- N Creative cùng Source → CT1_, CT2_, CT3_...
- N Creative → N Campaign.


---

# V1.6.2 — One-Click Campaign

Từ version này, `TEST PIPELINE` không còn là bước bắt buộc.

Luồng chính:

```text
Import Data
→ Chọn tất cả
→ Chọn Fanpage
→ TẠO CAMPAIGN AUTO
```

Tool tự chạy ngầm:

```text
PARSING SOURCE
→ GEMINI
→ SOURCE FIDELITY
→ QA
→ CONTENT
→ CREATIVE
→ CAMPAIGN
```

Cột `Pipeline Status` hiển thị live từng bước.

Nút `TEST PIPELINE` vẫn tồn tại để debug thủ công khi cần.

Shared Content rule giữ nguyên:

```text
1 Source group
→ 1 Gemini/QA landing content
→ 1 Ethopex content_id
→ N Creative
→ N Campaign
```

Nếu generated_content.json đã QA PASS, auto test dùng cache,
chạy lại Source Fidelity + QA và không tốn Gemini quota không cần thiết.


---

# V1.6.2.1 — Build Fix

Fix lỗi compile:

`CampaignWindowController has no member refreshPersistedStatuses`

Nguyên nhân: V1.6.2 gọi helper `refreshPersistedStatuses()` nhưng helper này chưa từng tồn tại trong `CampaignWindowController`.

Fix:
- bỏ call helper không tồn tại;
- giữ status live từ callback `onStatus`;
- redraw bảng bằng `tableView.reloadData()` sau khi AUTO pipeline hoàn tất.

Không thay đổi flow One-Click Campaign.


---

# V1.6.3 — New Import Status

Sau mỗi lần `Import Folder Hàng Loạt`, tool ghi lại batch import.

Chỉ Creative record thực sự mới được tạo trong batch mới nhất được đánh dấu:

`MỚI • READY`

Các record cũ hiển thị:

`CŨ • READY`

Nếu record thiếu dữ liệu:

`MỚI • INCOMPLETE` hoặc `CŨ • INCOMPLETE`

Campaign Automation có nút mới:

`Chọn DATA MỚI`

Nút này chọn toàn bộ record READY thuộc batch import mới nhất.
Không cần nhớ STT.

Nếu re-import đúng Creative đã tồn tại:
- không tạo duplicate;
- record đó vẫn là CŨ;
- không bị đánh dấu nhầm là DATA MỚI.

Nếu import thêm Creative mới cho Source cũ:
- Creative mới được đánh dấu MỚI;
- Content cũ vẫn được reuse theo shared-content rule;
- có thể bấm `Chọn DATA MỚI` → `TẠO CAMPAIGN AUTO`.

Sau một batch import mới hơn, batch trước tự động trở thành CŨ.
Metadata MỚI/CŨ được lưu trong `records.json`, nên đóng/mở app không mất trạng thái.


---

# V1.6.4 — Language Selector

Campaign Automation có 5 ô chọn: EN / RU / AR / RO / HR.

- Mặc định chọn cả 5.
- Bỏ tick EN để chỉ xử lý RU/AR/RO/HR records.
- Nếu EN vẫn tick nhưng record EN đã có campaign_id, duplicate protection hiện tại tự skip EN.
- Chỉ record thuộc language đang tick đi vào AUTO pipeline.
- Content identity = Source Group + Language, nên EN và RU không share content_id.
- Record cũ và import hiện tại mặc định EN.

Đây là Language Layer để nối với Multilingual Generator ở bước tiếp theo.


---

# V1.6.4.1 — Compact Language Dropdown

Update UI Campaign Automation:

- Bỏ 5 checkbox EN / RU / AR / RO / HR nằm thành một hàng riêng.
- Chuyển `Languages` lên cùng hàng với `Display link`, đúng vùng trống bên phải.
- Dùng dropdown nhỏ gọn.
- Trong dropdown hiển thị 5 ngôn ngữ: English, Russian, Arabic, Romanian, Croatian.
- Cho phép chọn nhiều ngôn ngữ; language đang chọn được đánh dấu bên trong menu.
- Luôn giữ ít nhất một ngôn ngữ được chọn.
- Nếu chọn đủ 5, nút hiển thị `Tất cả 5 ngôn ngữ`.
- Nếu chọn một phần, nút hiển thị dạng `RU / AR / RO / HR`.
- Selection tiếp tục lưu bằng UserDefaults như V1.6.4; không đổi logic Campaign.
- Thu gọn header trở lại vì không còn hàng checkbox language riêng.


---

# V1.6.5 — Professional UI

Bản này chỉ nâng cấp giao diện và trải nghiệm sử dụng, không thay đổi dữ liệu
hoặc workflow Campaign đang chạy ổn.

Các thay đổi chính:

- App shell mới gọn và hiện đại hơn.
- Background + card layout native macOS.
- Nút chính `TẠO CAMPAIGN AUTO` được nhấn mạnh rõ ràng.
- Các action phụ có icon và hierarchy rõ hơn.
- Header Campaign được gom thành một control card.
- Table Campaign và Data Manager bỏ border bezel cũ, tăng khoảng thở.
- `Data Status` và `Pipeline Status` hiển thị dạng badge/pill.
- Activity Log được chuyển thành panel monospaced gọn hơn.
- Data Manager có primary/secondary/danger button hierarchy.
- Detail panel, ảnh preview và các text panel đồng bộ style.
- UI tiếp tục dùng system colors nên tự thích nghi Light/Dark Mode.

Không thay đổi:
- records.json
- content_id / creative_id / campaign_id
- MỚI/CŨ
- Language selector
- shared Content
- Campaign Auto logic
- API configuration


---

# V1.6.5.1 — Language Multi-Select

Update phần chọn Language trong Campaign Automation:

- Dropdown Language đổi sang popover multi-select.
- Có nút `Chọn tất cả 5 ngôn ngữ`.
- Dropdown KHÔNG tự đóng sau khi tick một language.
- Có thể tick/bỏ tick EN, RU, AR, RO, HR liên tục trong cùng một lần mở.
- Popover chỉ đóng khi click ra ngoài hoặc click lại nút Language.
- Vẫn bắt buộc giữ tối thiểu 1 language để tránh Campaign Auto chạy với lựa chọn rỗng.
- Tiêu đề nút tự cập nhật:
  - `Tất cả 5 ngôn ngữ`
  - hoặc `RU / AR / RO / HR`, v.v.

Không thay đổi Campaign logic, Content/Creative/Campaign state hay dữ liệu hiện có.


---

# V1.6.6 — Operations Dashboard

Mục tiêu của bản này là đưa Campaign Automation gần hơn với giao diện của
một sản phẩm production có nhiều người dùng: nhìn nhanh được toàn bộ hệ thống,
đồng thời theo dõi chính xác record đang dừng ở bước nào.

## Operations Overview

Thêm dashboard card gồm:

- Total
- New Data
- Selected
- Running
- Campaigns
- Failed

Có progress bar `campaigns created / total`.

## Detailed Pipeline Monitoring

Mỗi record có status riêng cho từng stage:

- Data
- Source
- Gemini
- QA
- Content
- Image
- Creative
- Campaign
- Overall

Ví dụ status:

- WAITING
- RUNNING
- PARSED
- DONE
- CHECKING
- PASSED
- READY
- CREATING
- UPLOADING
- UPLOADED
- CREATED
- BLOCKED
- FAILED / ERROR

Status được tính từ `integration_state.json` hiện có và live `JobStatus`;
không tạo thêm database mới.

Hover lên stage sẽ hiển thị thông tin hữu ích nếu có:

- content_id
- media_id / uploaded image URL
- creative_id
- campaign_id / ad_set_id / ad_id
- lastError / creativeBlocker

## UI

- Workspace mặc định rộng hơn để theo dõi nhiều stage.
- Table có horizontal scroll khi màn hình nhỏ.
- Stage status dùng badge màu thống nhất:
  - xanh dương = đang xử lý
  - xanh lá = hoàn tất
  - cam = sẵn sàng/chờ bước tiếp theo
  - đỏ = lỗi/block
  - xám = chưa chạy

Không thay đổi records.json, API credentials, Content/Creative/Campaign flow,
shared Content, Language multi-select hay logic chống duplicate.


---

# V1.6.6.1 — Campaign Name From Creative

Rule mới:

`Campaign Name = Creative/Data Record Name`

Ví dụ:

`CT1_WHICH GREEK GOD IS THAT`
→ Creative: `CT1_WHICH GREEK GOD IS THAT`
→ Campaign: `CT1_WHICH GREEK GOD IS THAT`

`CT2_WHICH GREEK GOD IS THAT`
→ Campaign: `CT2_WHICH GREEK GOD IS THAT`

Mục tiêu:
- nhìn Campaign là biết ngay Campaign được tạo từ Creative nào;
- giữ nguyên CT1 / CT2 / CT3... giữa Data Manager → Creative → Campaign;
- tránh nhiều Campaign của các Creative variant dùng chung một technical landing name.

Generated landing JSON `name` không còn được ưu tiên khi đặt Campaign name.
Nó chỉ là fallback nếu record name bị rỗng bất thường.

Lưu ý:
- áp dụng cho Campaign được tạo mới từ version này;
- Campaign đã tạo trước đó và đã có campaign_id vẫn được chống duplicate và không tự rename.


---

# V1.6.6.2 — Language Technical Name

Thay rule technical name cũ:

`Greek_God_Testw1`

bằng technical name theo ngôn ngữ:

- English → `Greek_God_EN`
- Russian → `Greek_God_RU`
- Arabic → `Greek_God_AR`
- Romanian → `Greek_God_RO`
- Croatian → `Greek_God_HR`

Rule áp dụng cho root `name` trong `generated_content.json`.

Tool không chỉ yêu cầu Gemini làm đúng mà còn canonicalize deterministic sau
khi nhận JSON, nên cache cũ dạng `_Testw1` cũng tự được migrate ở lần pipeline
tiếp theo mà không cần tốn thêm Gemini quota nếu cache đang hợp lệ.

QA cũng được đổi:
- không còn yêu cầu `_Testw1`;
- bắt buộc suffix khớp root `locale`;
- reject suffix full language name cũ.

Campaign Name vẫn giữ rule V1.6.6.1:
`Campaign Name = Creative/Data Record Name`.


---

# V1.6.6.3 — Suffix Compile Fix

Fix lỗi macOS compile trong `QuizQA.swift`:

Sai:
`name.localizedCaseInsensitiveHasSuffix(suffix)`

`String` không có method này.

Đúng:
`name.lowercased().hasSuffix(suffix.lowercased())`

Warning `allowedFileTypes` deprecated trong `CombinedMain.swift` chỉ là warning,
không phải nguyên nhân làm build dừng.

Đây là cumulative update từ V1.6.6, nên bao gồm luôn:
- V1.6.6.1 Campaign Name = Creative/Data Name
- V1.6.6.2 technical name theo language: `_EN/_RU/_AR/_RO/_HR`
- V1.6.6.3 compile fix


---

# V1.6.6.4 — Responsive Layout / Fit Screen

Fix tình trạng app bị tràn màn hình và khó thu nhỏ.

## Workspace window
- Không còn mở cố định ở 1680×960.
- Tự đo kích thước `NSScreen.visibleFrame`.
- Mặc định mở vừa màn hình hiện tại.
- Giảm minimum window size đáng kể.
- Title/subtitle tự truncate thay vì ép window rộng ra.

## Data Manager
- Split View resize tự do hơn.
- Left panel có minimum nhỏ hơn.
- Bảng bên trái có horizontal scroll khi panel hẹp.
- Right detail panel có vertical scroll.
- Long Name / Source / Image filename tự truncate.
- Action buttons không còn nằm cùng hàng với long title.
- Image metadata chuyển xuống dưới preview, không ép chiều ngang.
- Search + bottom actions được compact để fit màn hình nhỏ.

## Campaign Automation
- Standalone window cũng tự fit màn hình.
- Giảm minimum size.
- Control widths compact.
- Language + summary chuyển xuống row riêng.
- Table vẫn horizontal-scroll được khi có nhiều stage columns.
- Header text/status tự truncate để tránh constraint overflow.

## Build
- Zip picker đổi từ `allowedFileTypes` sang `allowedContentTypes = [.zip]`,
  loại bỏ warning deprecated đã thấy ở build trước.

Không thay đổi data, API state, Content/Creative/Campaign logic,
Language routing, naming rules hay duplicate protection.


---

# V1.6.7 — Professional Balanced UI

Campaign header được thiết kế lại hoàn toàn theo kiểu app production.

## Bố cục mới

Header chia thành 2 vùng cân bằng:

### DATA & WORKFLOW
- Search
- Refresh
- Select All
- DATA mới
- Clear
- Step 1 Test
- Step 2 Content
- Step 3 Creative
- READY / Selected / Language summary

### CAMPAIGN SETUP
- Display Link
- Language multi-select
- Fanpage
- Refresh Pages
- API Settings
- Step 4 `TẠO CAMPAIGN AUTO` full-width CTA

Không còn tình trạng toàn bộ button dồn bên trái và bên phải trống.

## Visual system

- DATA & WORKFLOW có blue tint card.
- CAMPAIGN SETUP có purple tint card.
- DATA mới dùng purple accent.
- Test dùng orange accent.
- Content dùng blue accent.
- Creative dùng purple accent.
- API dùng teal accent.
- Campaign Auto là primary blue CTA duy nhất.
- Gemini/Ethopex READY hiển thị thành status pill có nền/border màu.

Màu được dùng có hierarchy, không tô tất cả button thành nhiều màu mạnh.

Không thay đổi:
- records.json
- API logic
- Campaign pipeline
- Language selector logic
- Template routing
- Content/Creative/Campaign IDs
- duplicate protection
- responsive layout V1.6.6.4


---

# V1.6.7.1 — Three Panel Header

Fix trực tiếp vấn đề V1.6.7 vẫn còn vùng trống lớn.

Header Campaign Automation được chia thành 3 panel thực sự:

1. DATA SELECTION
   - Search
   - Select All
   - DATA mới
   - Clear
   - Refresh
   - READY / Selected / Language summary

2. PIPELINE FLOW
   - Test Pipeline
   - Content
   - Creative
   - Flow hint: Source → Gemini → QA → Content → Image → Creative → Campaign

3. CAMPAIGN SETUP
   - Display Link
   - Language
   - Fanpage
   - Pages
   - API
   - TẠO CAMPAIGN AUTO

Tỷ lệ mặc định khoảng 36% / 28% / 36%.

Không còn một panel trái cực rộng với button dồn ở góc trên.
Không thay đổi pipeline/data logic.


---

# V1.6.7.2 — Data Manager Split Stability

Fix lỗi Data Manager bị "nhảy giao diện" khi chọn record khác.

Nguyên nhân:
- record khác nhau có Name / Source / Image filename / Headline dài ngắn khác nhau;
- AppKit tính lại fitting width của detail pane;
- pane phải có thể co giãn nên divider bị đẩy trái/phải theo content.

Fix:
- NSSplitView được giữ thành controller state;
- trước khi đổi record, lưu chính xác divider position;
- sau khi render detail, restore divider position;
- restore thêm lần nữa ở next runloop để chống fitting-size recalculation;
- giữ horizontal scroll position của bảng trái;
- long labels có low compression resistance và truncate trong pane;
- detail content co theo pane, không được ép pane rộng ra;
- vertical detail scroll chỉ reset về top.

Kết quả:
- click record ngắn/dài không đổi chiều rộng hai panel;
- user kéo divider tới đâu thì click record tiếp theo vẫn giữ nguyên;
- bảng trái không tự nhảy ngang.


---

# V1.6.7.3 — Responsive Centered Campaign

Fix triệt để overflow ở Campaign Automation header.

## Nguyên nhân bản cũ
Header dùng nhiều fixed/minimum-width constraint cùng lúc.
Khi cửa sổ nhỏ hơn tổng minimum width, AppKit buộc phần bên phải vượt khỏi visible area.

## Bố cục mới
Header dùng `NSStackView` horizontal với `.fillEqually`:

`DATA SELECTION | CAMPAIGN SETUP | PIPELINE FLOW`

Campaign Setup nằm chính giữa theo yêu cầu.

Mỗi panel luôn nhận cùng chiều rộng thực tế và tự co theo cửa sổ.
Không còn rigid ratio 36/28/36 và không còn minimum-width ép tràn.

## Controls bên trong
- Data panel: search full width, selection row, refresh + summary.
- Campaign panel: Display Link / Languages / Fanpage xếp dọc full width,
  sau đó Campaign Auto.
- Pipeline panel: Test / Content / Creative xếp dọc full width.
- Long text/popups có low compression resistance để tự truncate/co lại.

Kết quả:
- resize cửa sổ không làm panel phải bị cắt;
- Campaign Setup luôn ở giữa;
- ba panel cân bằng;
- không cần horizontal scroll cho header.

Không thay đổi Data/Campaign logic.


---

# V1.6.7.4 — Vertical Fit + Slim Scrollbars

- LIVE ACTIVITY luôn nằm trong vùng nhìn thấy.
- Header/Overview/Log được compact lại để không vượt chiều cao container.
- Records table là vùng co giãn chính và tự scroll nội bộ.
- Horizontal scrollbar của table chuyển sang overlay + small.
- Vertical scrollbar của LIVE ACTIVITY cũng chuyển overlay + small.
- Bottom inset nhỏ giúp scrollbar không che hàng cuối.
- Campaign Setup vẫn ở giữa.


---

# V1.6.7.5 — Table Column Alignment

Fix lệch giữa tiêu đề cột và nội dung trong Campaign Automation.

- STT / Lang / Data / Source / Gemini / QA / Content / Image /
  Creative / Campaign / Overall: header + body đều căn giữa.
- Creative / Data và Source View: giữ căn trái.
- Lang body được căn giữa.
- Status badge dùng cùng tâm cột với header.
- Insets status columns đồng nhất 6pt hai bên.
- Column boundary và body boundary giữ cùng horizontal spacing.

Không thay đổi pipeline/status logic.


---

# V1.6.7.6 — Campaign Button Fit

Fix lỗi nút `4 TẠO CAMPAIGN AUTO` bị clip/mất ở Campaign Setup.

Nguyên nhân:
- V1.6.7.3–1.6.7.5 xếp Display Link, Language, Fanpage và CTA theo một
  vertical chain quá cao so với chiều cao thật của center panel.
- Header tổng vẫn fit màn hình, nhưng nội dung bên trong Campaign Setup vượt
  quá chiều cao panel nên CTA chỉ còn một đường xanh mỏng.

Fix:
- Display Link + Languages chuyển sang cùng một hàng 2 cột.
- Fanpage ở hàng tiếp theo.
- Campaign Auto ở hàng cuối, full width.
- CTA có bottom constraint bắt buộc nằm trong panel.
- Có runtime layout warning trong LIVE ACTIVITY nếu AppKit vẫn phát hiện CTA
  vượt khỏi bounds của Campaign Setup.

Không thay đổi Campaign logic/API/data.


---

# V1.6.7.7 — Vertical Text Centering

Fix lỗi text trong status pill nhìn bị lệch lên phía trên.

Nguyên nhân:
`NSTextField` / `NSTextFieldCell` của AppKit không tự căn giữa vertical
theo fixed-height badge như button native. AutoLayout chỉ center frame,
không center baseline text bên trong frame.

Fix:
- thêm `WorkspaceVerticallyCenteredTextFieldCell`;
- override `drawingRect(forBounds:)` để tính lại baseline theo chiều cao text;
- mọi badge Data / Source / Gemini / QA / Content / Image /
  Creative / Campaign / Overall dùng cell này;
- API status pill `Gemini READY • Ethopex READY` dùng cùng rule;
- STT / Lang / text cell cũng dùng baseline center thống nhất;
- badge height từ 24 → 26 để có optical padding đều trên/dưới.

Không thay đổi pipeline, Campaign API, data hay status logic.


---

# V1.7.0 — Multilingual Engine (EN / RU / AR / RO / HR)

Đây là bản nối thật phần Language vào core automation, không còn chỉ là UI filter.

## One-click multilingual
Khi chọn Creative/Data nguồn + chọn languages rồi bấm `4 TẠO CAMPAIGN AUTO`:

1. Detect language thật từ Source View.
2. Với language gốc: tái sử dụng Creative gốc, không dịch lại.
3. Với language khác:
   - Gemini dịch Primary Text / Headline / Description.
   - Gemini Image (`gemini-3.1-flash-image`) edit ảnh gốc sang language đích, 1:1, 2K.
   - Tạo persistent language variant trong Data Manager.
4. Landing Page Gemini chạy theo target language.
5. Content tách theo Source + language; Creative variants cùng language vẫn share 1 Content.
6. Image localized được upload lên Ethopex R2 và dùng cho Creative tương ứng.
7. Campaign tự route template theo language.

## Template routing khóa
- EN → `Template_ETP_300_EN` → ad_account `3727435` → external `1730366391509645` → locales AUTO
- RU → `Template_ETP_301_RU` → ad_account `3727428` → external `1366664018402867` → locales `[17]`
- AR → `Template_ETP_302_AR` → ad_account `3727434` → external `1423878659586190` → locales `[28]`
- RO → `Template_ETP_303_RO` → ad_account `3727429` → external `1022535590782431` → locales `[32]`
- HR → `Template_ETP_304_HR` → ad_account `3727441` → external `1072505841928283` → locales `[38]`

Payload được validate trước POST. Nếu account/locale routing không đúng thì dừng với `TEMPLATE MISMATCH`.

## Duplicate protection
- Existing EN Campaign giữ nguyên và skip như rule user yêu cầu.
- RU/AR/RO/HR chỉ skip khi Campaign state đã có đúng Fanpage + đúng template language.
- Language variant đã được tạo trước đó sẽ tái sử dụng; không gọi lại Image API/Ad Copy translation không cần thiết.

## Naming
- Technical landing name: `_EN / _RU / _AR / _RO / _HR`.
- Generated Creative variant: `<creative-name>_RU`, `<creative-name>_AR`, ...
- Campaign Name = Creative/Data Record Name nên nhìn Campaign biết Creative + language.

## Lưu ý test
Cross-language Landing Page dùng structured multilingual generation + Localized QA để giữ layout/question structure. Same-language vẫn dùng Source Fidelity Lock exact như cũ.


---

# V1.7.1 — Landing Language Guard

Fix trường hợp landing RO/RU/AR/HR có title/intro đã dịch nhưng question cards vẫn còn English/source language.

- Localized QA nhận luôn ParsedQuiz gốc để so sánh.
- Nếu qtext localized trùng nguyên văn Source View khi target khác source → FAIL.
- Có heuristic phát hiện English residue cho câu hỏi/option dài/explanation.
- RU yêu cầu question prose có Cyrillic khi có dấu hiệu English.
- AR yêu cầu question prose có Arabic script khi có dấu hiệu English.
- RO/HR dùng English-vs-target marker guard cho sentence-level residue.
- Cache multilingual cũ từ V1.7.0 được re-check. Nếu fail sẽ tự invalidate và regenerate ngay trong cùng lượt chạy.
- Mỗi Gemini attempt phải PASS Language Guard trước khi generated_content.json được chấp nhận. Attempt 1 fail → tự retry attempt 2.
- Content API/Campaign không chạy nếu landing target language chưa PASS.
- Image localization V1.7.0 được giữ nguyên; không hạ cấp hay bỏ qua image target-language generation.


---

# V1.7.2 — Multilingual AUTO Run Timer

Thêm bộ đo thời gian cho nút `4 TẠO CAMPAIGN AUTO`.

Khi user bắt đầu Multilingual AUTO:
- timer bắt đầu ngay sau khi xác nhận chạy;
- Pipeline Overview hiển thị `RUN HH:MM:SS` và cập nhật mỗi giây;
- log ghi giờ bắt đầu và batch scope.

Khi batch hoàn tất:
- UI hiển thị `DONE HH:MM:SS`;
- log ghi giờ hoàn tất + tổng thời gian;
- nếu có prepared language variants, log thêm average time / variant;
- hover timer xem Started / Finished / Total / Prepared variants / Average;
- thời gian lần chạy gần nhất được lưu để app mở lại có thể hiển thị `LAST HH:MM:SS`.

Nếu language preparation thất bại hoàn toàn:
- timer kết thúc với `FAILED HH:MM:SS`.

Timer chỉ đo Multilingual AUTO chính, không thay đổi Content/Creative/Campaign logic.


---

# V1.7.3 — Run-Scoped Overview

Fix `PIPELINE OVERVIEW` ghi nhận số liệu lịch sử của toàn bộ Data Manager.

Từ bản này dashboard đổi thành `CURRENT RUN OVERVIEW`.

Mỗi lần bấm `4 TẠO CAMPAIGN AUTO` và xác nhận chạy:
- reset toàn bộ metric của run trước;
- `Run Total` = source được chọn × language được chọn;
- `New Variants` = record language mới thực sự tạo trong run này;
- `Selected` = số variant thuộc run hiện tại;
- `Running` = job đang active trong run hiện tại;
- `Created` = campaign mới tạo trong run hiện tại, không cộng campaign cũ đã tồn tại;
- `Failed` = lỗi của run hiện tại + lỗi ở bước language preparation;
- progress bar = số variant đã xử lý / tổng variant của run.

Campaign cũ được SKIP vẫn được tính là `processed` để progress của batch hoàn tất,
nhưng KHÔNG cộng vào `Created`.

Khi run hoàn tất, dashboard giữ snapshot cuối của run đó.
Khi bắt đầu run tiếp theo, dashboard reset về 0 và bắt đầu tính lại từ đầu.

Trước khi có AUTO run đầu tiên trong app session:
- historical Campaign / Failed không còn được đưa vào overview;
- dashboard hiển thị `No current run`.


---

# V1.7.4 — Batched Landing Repair

Mục tiêu: giảm mạnh tỷ lệ fail của Landing multilingual khi Gemini trả
full landing đúng cấu trúc nhưng còn giữ qtext/explanation ở source language.

## Landing pipeline mới

Cross-language vẫn tạo full landing skeleton một lần để giữ:
- CSS / page structure;
- title / intro / footer / navigation;
- 20-question selection;
- image URL và option/correct classes.

Nếu `LANGUAGE GUARD` chỉ phát hiện question-card language residue:

1. Không vứt cả landing.
2. Extract 20 card.
3. Chia thành 4 batch × 5 question.
4. Dịch riêng:
   - qtext;
   - 4 options, giữ nguyên order;
   - explanation;
   - hint.
5. Merge deterministic vào đúng card.
6. Correct-answer class/index và image không bị thay đổi.
7. Chạy lại LANGUAGE GUARD.
8. Chỉ khi repair vẫn fail mới dùng full-generation retry.

Mỗi batch thành công được cache:
`landing_translation_<lang>_batch_XX.json`

Run sau có cùng input sẽ reuse cache.

## Retry / network

- Question batch: tối đa 3 attempts.
- Ad Copy: tối đa 3 attempts.
- Image localization: tối đa 3 attempts.
- HTTP 429/500/502/503/504 và network error dùng backoff trước retry.
- Một language prep fail không còn hủy các language còn lại của cùng source.

## Failure accounting

`Root Failed` chỉ phản ánh lỗi gốc của variant.
Nếu Landing/QA fail:
- Content → `CASCADE SKIP CONTENT`
- Creative → `CASCADE SKIP CREATIVE`
- Campaign → `CASCADE SKIP CAMPAIGN`

Các cascade skip không tạo thêm một lỗi gốc mới.

## Không thay đổi

- Image localization model / 2K / 1:1;
- Ad Copy localization;
- Template routing EN/RU/AR/RO/HR;
- Campaign Name = Creative record name;
- source/content duplicate rules;
- Run Timer;
- Current Run Overview.
