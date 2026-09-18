# ETHOPEX WORKSPACE UPDATE PACKAGE — FORMAT V1

Từ Ethopex Workspace V1.6 trở đi, không cần tải lại full app cho mỗi update.

ChatGPT sẽ gửi một ZIP nhỏ dạng:

```text
EthopexWorkspace_Update_v1.7.zip
└── EthopexWorkspaceUpdate/
    ├── update_manifest.json
    └── payload/
        ├── CampaignEngine.swift
        ├── DataManagerModule.swift
        └── ... chỉ các file thay đổi
```

Manifest:

```json
{
  "app": "EthopexWorkspace",
  "version": "1.7",
  "minimum_version": "1.6",
  "files": [
    "CampaignEngine.swift",
    "DataManagerModule.swift"
  ],
  "delete_paths": []
}
```

Cách dùng:

1. Mở Ethopex Workspace.
2. Bấm `UPDATE VERSION`.
3. Chọn ZIP update ChatGPT gửi.
4. Tool kiểm tra version và package.
5. Tool backup file source hiện tại vào `update_backups/`.
6. Tool gắn payload.
7. Tool đóng app, chạy lại `build.command`.
8. Version mới tự mở.

Lưu ý:

- Updater cần app được chạy từ project build bằng `build.command`.
- Tool không tải code từ Internet.
- Chỉ package có `app = EthopexWorkspace` và version cao hơn mới được nhận.
- Path tuyệt đối / `..` bị chặn.
- Nếu copy update lỗi, tool cố gắng rollback từ backup.
- Nếu build version mới lỗi, xem `update_build.log` hoặc chạy `build.command` thủ công.
