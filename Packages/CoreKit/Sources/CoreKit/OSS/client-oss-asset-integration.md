# 客户端 OSS 素材接入说明

本文档给 iOS/Android 客户端接入“历史素材 + 我的 OSS 资产”使用。

目标：

- 用户选择相册前，先进入历史素材页。
- 历史素材页同时展示客户端本地历史和服务端我的资产。
- 用户可以复用已上传 OSS 的素材，减少重复上传。
- 用户可以删除自己上传的 OSS 素材。
- 图片、视频详情页不直接拼 OSS 永久 URL，统一使用服务端返回的短期签名 URL。

---

## 1. 历史素材页展示策略

历史素材页建议分两个区域或两个 Tab：

### 1.1 本地历史

来源：客户端本地数据库或缓存。

内容：用户曾经选择过但未上传 OSS 的图片、视频。

建议字段：

```json
{
  "local_id": "local_xxx",
  "local_uri": "ph://xxx 或 file://xxx",
  "asset_kind": "image",
  "filename": "IMG_0001.JPG",
  "size_bytes": 123456,
  "created_at": "2026-05-15T10:00:00+08:00",
  "uploaded": false
}
```

规则：

- 本地历史只在当前设备可用。
- 服务端无法删除本地历史，删除本地历史由客户端自己处理。
- 用户选择本地历史发起任务前，如果服务端需要 URL，必须先走新上传流程上传到 OSS。

### 1.2 我的资产

来源：服务端 `/api/v1/assets`。

内容：用户已上传到 OSS 的素材。

规则：

- 只展示当前登录用户自己的资产。
- 服务端返回的 `url` 是短期签名 URL，客户端不要长期保存。
- 客户端可以缓存资产元信息，但不要缓存 `url` 作为永久地址。
- `url_expires_at` 到期前可以直接展示；到期或加载失败时重新请求资产列表或任务详情刷新 URL。

---

## 2. 给用户的有效期提示

客户端需要明确告诉用户：

> 已上传素材会在云端保存一段时间，建议及时保存重要素材。删除素材或云端保存期结束后，可能无法继续从历史素材中使用。

当前建议文案：

- 我的素材：云端素材会保存一段时间，重要内容请及时保存到本地。
- 本地历史：仅保存在当前设备，卸载 App 或清理缓存后可能丢失。
- 生成过程素材：仅用于本次任务处理，通常会在短时间内自动清理。
- 生成结果：当前默认由服务端保存，后续可能按会员等级或产品策略设置保留期。

当前服务端默认清理策略：

| 类型 | 服务端策略 |
| --- | --- |
| 用户上传素材 `user_upload` | 用户主动删除；后续可按产品策略设置保留期 |
| 任务中转素材 `task_intermediate` | 默认 24 小时清理 |
| 服务商可访问素材 `provider_access` | 默认 24 小时清理 |
| 缓存素材 `cache` | 默认 7 天清理 |
| 审核素材 `audit` | 默认 30 天清理 |
| 管理员运营素材 `admin_catalog` | 长期保护，不自动清理 |

---

## 3. 统一响应格式

接口成功统一返回：

```json
{
  "trace_id": "trace_xxx",
  "code": 0,
  "msg": "success",
  "data": {}
}
```

客户端只在 `code == 0` 时读取 `data`。

所有接口都需要登录态：

```http
Authorization: Bearer <access_token>
```

---

## 4. 上传流程

客户端上传用户素材必须使用新流程，不再直接使用旧 `/auth/oss/sts` 自己拼目录。

### 4.1 初始化上传

```http
POST /api/v1/uploads/init
Content-Type: application/json
Authorization: Bearer <access_token>
```

请求：

```json
{
  "asset_class": "user_upload",
  "asset_kind": "image",
  "filename": "IMG_0001.JPG",
  "content_type": "image/jpeg",
  "size_bytes": 123456,
  "business_type": "material_picker"
}
```

字段说明：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `asset_class` | 是 | 客户端只能传 `user_upload` |
| `asset_kind` | 是 | `image` / `video` / `audio` / `file` |
| `filename` | 是 | 原始文件名，服务端会清理并生成最终对象名 |
| `content_type` | 否 | MIME 类型，例如 `image/jpeg`、`video/mp4` |
| `size_bytes` | 否 | 文件大小 |
| `business_type` | 否 | 业务来源，例如 `material_picker`、`task_input` |

响应 `data`：

```json
{
  "asset_id": 10001,
  "upload_id": "up_xxx",
  "bucket": "dreamlog",
  "region": "cn-beijing",
  "endpoint": "oss-cn-beijing.aliyuncs.com",
  "host": "https://dreamlog.oss-cn-beijing.aliyuncs.com",
  "dir": "prod/private/user-upload/user/123/2026/05/15/up_xxx/",
  "object_key": "prod/private/user-upload/user/123/2026/05/15/up_xxx/IMG_0001_abcd.jpg",
  "sts": {
    "access_key_id": "STS.xxx",
    "access_key_secret": "xxx",
    "security_token": "xxx",
    "expiration": "2026-05-15T11:00:00Z"
  },
  "asset": {
    "asset_id": 10001,
    "url": "",
    "oss_key": "prod/private/user-upload/user/123/2026/05/15/up_xxx/IMG_0001_abcd.jpg",
    "bucket": "dreamlog",
    "asset_class": "user_upload",
    "asset_kind": "image",
    "visibility": "private",
    "filename": "IMG_0001_abcd.jpg",
    "size_bytes": 123456,
    "content_type": "image/jpeg",
    "status": "pending",
    "can_delete": true,
    "ref_count": 0,
    "created_at": "2026-05-15T10:00:00+08:00"
  }
}
```

### 4.2 OSS SDK 直传

客户端使用响应中的 STS 临时凭证上传到指定 `bucket` 和 `object_key`。

关键规则：

- 必须上传到服务端返回的 `object_key`。
- 不允许客户端自己拼目录。
- 不允许把文件上传到其他 bucket 或其他 key。
- STS 只允许写入本次初始化返回的对象。
- 上传时建议设置 `Content-Type`。

iOS 侧概念流程：

```swift
// 伪代码，仅表达流程
let initRes = POST("/api/v1/uploads/init")

let credentialProvider = OSSStsTokenCredentialProvider(
    accessKeyId: initRes.sts.access_key_id,
    secretKeyId: initRes.sts.access_key_secret,
    securityToken: initRes.sts.security_token
)

let client = OSSClient(endpoint: initRes.endpoint, credentialProvider: credentialProvider)
let request = OSSPutObjectRequest()
request.bucketName = initRes.bucket
request.objectKey = initRes.object_key
request.uploadingFileURL = localFileURL
request.contentType = contentType

client.putObject(request)
```

### 4.3 完成上传

OSS SDK 上传成功后，必须调用完成接口。

```http
POST /api/v1/uploads/complete
Content-Type: application/json
Authorization: Bearer <access_token>
```

请求：

```json
{
  "asset_id": 10001,
  "upload_id": "up_xxx",
  "oss_key": "prod/private/user-upload/user/123/2026/05/15/up_xxx/IMG_0001_abcd.jpg"
}
```

响应 `data`：

```json
{
  "asset_id": 10001,
  "url": "https://dreamlog.oss-cn-beijing.aliyuncs.com/prod/private/...?Expires=...",
  "url_expires_at": "2026-05-15T10:30:00+08:00",
  "oss_key": "prod/private/user-upload/user/123/2026/05/15/up_xxx/IMG_0001_abcd.jpg",
  "bucket": "dreamlog",
  "asset_class": "user_upload",
  "asset_kind": "image",
  "visibility": "private",
  "filename": "IMG_0001_abcd.jpg",
  "size_bytes": 123456,
  "content_type": "image/jpeg",
  "status": "active",
  "can_delete": true,
  "ref_count": 0,
  "created_at": "2026-05-15T10:00:00+08:00"
}
```

完成接口会做 `HeadObject` 校验。客户端只有拿到 `status=active` 后，才能把该素材作为“我的资产”使用。

---

## 5. 查看我的资产列表

```http
GET /api/v1/assets?asset_class=user_upload&asset_kind=image&page=1&page_size=20
Authorization: Bearer <access_token>
```

查询参数：

| 参数 | 说明 |
| --- | --- |
| `asset_class` | 当前可传 `user_upload`，服务端目前只返回用户上传资产 |
| `asset_kind` | 可选：`image` / `video` / `audio` / `file` |
| `page` | 页码，默认 1 |
| `page_size` | 每页数量，默认 20，最大 100 |

响应 `data`：

```json
{
  "items": [
    {
      "asset_id": 10001,
      "url": "https://dreamlog.oss-cn-beijing.aliyuncs.com/prod/private/...?Expires=...",
      "url_expires_at": "2026-05-15T10:30:00+08:00",
      "oss_key": "prod/private/user-upload/user/123/2026/05/15/up_xxx/IMG_0001_abcd.jpg",
      "bucket": "dreamlog",
      "asset_class": "user_upload",
      "asset_kind": "image",
      "visibility": "private",
      "filename": "IMG_0001_abcd.jpg",
      "size_bytes": 123456,
      "content_type": "image/jpeg",
      "status": "active",
      "can_delete": true,
      "ref_count": 0,
      "created_at": "2026-05-15T10:00:00+08:00"
    }
  ],
  "page": 1,
  "page_size": 20,
  "total": 1
}
```

客户端展示规则：

- 图片/视频缩略图使用 `url` 加载。
- `url_expires_at` 快过期或已经过期时，重新请求列表刷新。
- 列表下拉刷新时直接重新拉取服务端资产，不要复用旧签名 URL。
- 本地可以保存 `asset_id`、`asset_kind`、`filename`、`size_bytes`、`created_at`，但不要把 `url` 当永久地址保存。

---

## 6. 删除我的资产

```http
DELETE /api/v1/assets/{asset_id}
Authorization: Bearer <access_token>
```

响应 `data`：

```json
{
  "asset_id": 10001,
  "delete_mode": "physical",
  "status": "deleted"
}
```

可能的 `delete_mode`：

| delete_mode | 含义 | 客户端处理 |
| --- | --- | --- |
| `physical` | OSS 对象已物理删除 | 从列表移除 |
| `soft` | 素材被引用，仅从素材库移除或标记删除 | 从列表移除，并提示“素材已被使用，云端会在安全时机清理” |

删除规则：

- 普通用户只能删除自己的 `user_upload`。
- 管理员运营素材、任务中转文件、任务结果不能通过该接口删除。
- 如果素材已经被任务引用，服务端可能软删除，避免破坏历史任务。

---

## 7. 发起任务时如何传素材

### 7.1 使用本地历史素材

如果素材只在本地，发起任务前必须先上传：

1. `/uploads/init`
2. OSS SDK 直传
3. `/uploads/complete`
4. 使用完成接口返回的 `url` 或服务端约定的业务输入字段发起任务

### 7.2 使用我的资产

如果素材已经是我的资产：

- 优先使用 `asset_id` 作为内部追踪字段。
- 当前工作流如果只接受 URL，则使用资产列表返回的短期 `url`。
- 如果提交任务前 `url_expires_at` 已接近过期，先刷新资产列表再提交。

建议客户端内部模型：

```json
{
  "source": "remote_asset",
  "asset_id": 10001,
  "asset_kind": "image",
  "url": "短期签名 URL",
  "url_expires_at": "2026-05-15T10:30:00+08:00"
}
```

后续服务端可以逐步支持任务输入直接传 `asset_id`，届时客户端不需要关心 URL 刷新。

---

## 8. 任务详情和创作过程加载规则

详情页接口：

```http
GET /api/v1/user/works/info/{task_id}
Authorization: Bearer <access_token>
```

创作过程节点接口：

```http
GET /api/v1/user/works/{task_id}/nodes-def/{node}
GET /api/v1/user/works/{task_id}/nodes/{node}
Authorization: Bearer <access_token>
```

规则：

- 客户端不要自己拼 OSS URL。
- 服务端会在返回的 `input`、`result`、节点输出等结构中，把已入资产台账的私有 OSS URL 转换成短期签名 URL。
- `internal` 中转素材会被服务端隐藏或置空，客户端不应展示。
- 其他用户的私有素材会被服务端置空，客户端应按资源不可访问处理。
- 签名 URL 过期后，客户端重新请求详情或节点接口刷新。

图片加载：

- 可以继续用 `KFImage` 或原生加载，但 URL 必须是服务端返回的短期签名 URL。
- 不要用 `bucket + oss_key` 自己拼接。
- 加载 403、404、签名过期时，重新请求业务接口刷新 URL。

视频加载：

- 使用服务端返回的短期签名 URL 初始化播放器。
- 播放长视频时，如果 URL 过期导致播放失败，重新请求详情刷新 URL 后重建播放源。
- 不建议把签名 URL 下载后长期缓存为云端地址；如需离线保存，应走用户主动保存到本地的产品逻辑。

---

## 9. 客户端鉴权规则

业务 API 鉴权：

- 所有 `/uploads/*`、`/assets`、`/user/works/*` 都需要登录 token。
- token 放在 `Authorization: Bearer <access_token>`。
- 登录过期按现有刷新 token 流程处理。

OSS SDK 上传鉴权：

- 客户端不使用长期 AK/SK。
- 客户端只使用 `/uploads/init` 返回的 STS 临时凭证。
- STS 只用于本次 `object_key` 上传。
- STS 过期后重新调用 `/uploads/init`，不要复用旧凭证。

OSS 资源查看鉴权：

- 客户端查看私有素材不需要 OSS SDK。
- 客户端使用服务端返回的短期签名 URL 直接加载图片/视频。
- 访问权限由服务端在业务接口中校验 owner 后生成签名 URL。

---

## 10. 服务端配置

当前推荐：

```yaml
alioss:
  accessmode: "public"
  signed_url_expire_seconds: 1800
  provider_url_expire_seconds: 7200
  cleanup_enabled: true
  cleanup_interval_seconds: 3600
  cleanup_batch_size: 100
  provider_access_retention_hours: 24
  task_intermediate_retention_hours: 24
  cache_retention_hours: 168
  audit_retention_hours: 720
  delete_retry_max: 5
  delete_retry_delay_seconds: 1800
```

说明：

| 配置 | 说明 |
| --- | --- |
| `accessmode=public` | 当前 Bucket 仍公开，服务商可用普通 OSS URL |
| `accessmode=private` | 未来 Bucket 私有后，`provider_access` 自动使用短期签名 URL |
| `signed_url_expire_seconds` | 客户端查看素材、详情页、创作过程的短签有效期 |
| `provider_url_expire_seconds` | 服务商拉取中转素材的短签有效期 |
| `cleanup_enabled` | 是否启用自动清理 |
| `provider_access_retention_hours` | 服务商可访问中转素材保留小时数 |
| `task_intermediate_retention_hours` | 内部中转素材保留小时数 |
| `cache_retention_hours` | 缓存素材保留小时数 |
| `audit_retention_hours` | 审核素材保留小时数 |

迁移私有 Bucket 时，先在测试环境改：

```yaml
alioss:
  accessmode: "private"
```

验证客户端上传、我的资产、任务详情、创作过程、服务商生成任务都正常后，再调整阿里云 OSS Bucket 权限。

---

## 11. 阿里云 OSS 控制台配置建议

### 11.1 当前上线前过渡期

如果历史首页和模板资源已经依赖公开 URL，可以暂时保持 Bucket 公开，但必须做到：

- 新用户上传路径进入 `prod/private/user-upload/...`
- 新任务结果进入 `prod/private/task-result/...`
- 服务商中转素材进入 `prod/provider-access/...`
- 内部中转和缓存进入 `prod/internal/...`
- 客户端不再自己拼接公开 URL。
- 服务端先完整记录资产台账。

### 11.2 推荐目标状态

更成熟的状态是拆 Bucket：

| Bucket | 权限 | 用途 |
| --- | --- | --- |
| public assets bucket | 公共读 | 首页 banner、模板封面、运营素材 |
| private user bucket | 私有 | 用户上传、用户生成结果 |
| transient bucket | 私有 | 服务商中转、内部临时文件 |
| audit bucket | 私有 | 审核、风控、隔离文件 |

短期不拆 Bucket 时，至少按前缀隔离：

```text
prod/public/admin/catalog/...
prod/private/user-upload/...
prod/private/task-result/...
prod/provider-access/task-input/...
prod/internal/task-temp/...
prod/internal/cache/...
prod/internal/audit/...
```

### 11.3 Bucket 权限

目标私有化时：

- Bucket ACL 设置为私有。
- 禁止匿名公共读。
- 公开运营资源要么放独立公开 Bucket，要么走 CDN 公开分发。
- 用户私有素材和任务中转素材不允许永久公开访问。

### 11.4 RAM/STS 权限

STS 角色需要最小权限：

- 允许客户端上传指定 object key：
  - `oss:PutObject`
  - `oss:InitiateMultipartUpload`
  - `oss:UploadPart`
  - `oss:CompleteMultipartUpload`
  - `oss:AbortMultipartUpload`
- 不给客户端 `oss:GetObject` 和 `oss:DeleteObject`。
- 不给客户端列表权限。
- 服务端通过 session policy 把资源限制到本次 `object_key`。

### 11.5 生命周期规则

OSS 控制台可额外配置生命周期作为兜底：

- `prod/internal/task-temp/`：1-3 天删除
- `prod/provider-access/`：1-3 天删除
- `prod/internal/cache/`：7-30 天删除
- `prod/internal/audit/`：按审核合规策略设置

注意：生命周期是兜底，业务侧仍以 `storage_objects` 台账清理为准。

### 11.6 防盗链和 CDN

公开资源建议：

- 开启 Referer 防盗链。
- 首页、模板、运营图可走 CDN。
- CDN 开启流量监控和异常告警。

私有资源建议：

- 不使用公共 CDN URL。
- 后续如需 CDN 加速，使用 CDN 鉴权 URL。
- 不把短期签名 URL 持久化到数据库或客户端长期缓存。

---

## 12. 客户端错误处理建议

| 场景 | 客户端处理 |
| --- | --- |
| `/uploads/init` 失败 | 提示上传初始化失败，可重试 |
| OSS SDK 上传失败 | 保留本地历史，提示重新上传 |
| `/uploads/complete` 失败 | 不把素材加入我的资产；可重试 complete |
| 图片/视频加载 403 | 签名可能过期，重新请求列表或详情 |
| 图片/视频加载 404 | 素材可能已删除或过期，提示不可用 |
| 删除返回 soft | 从我的资产列表移除，提示素材已被引用 |
| 登录过期 | 走刷新 token 或重新登录 |

---

## 13. 客户端接入检查清单

- [ ] 历史素材页展示本地历史和我的资产。
- [ ] 本地历史发起任务前先上传 OSS。
- [ ] 上传使用 `/uploads/init` + OSS SDK + `/uploads/complete`。
- [ ] 不再使用旧 `/auth/oss/sts` 作为用户素材上传入口。
- [ ] 我的资产列表使用 `/api/v1/assets`。
- [ ] 删除我的资产使用 `DELETE /api/v1/assets/{asset_id}`。
- [ ] 图片和视频加载使用服务端返回的短期签名 URL。
- [ ] `url_expires_at` 过期后重新请求服务端刷新。
- [ ] 不持久化短期签名 URL。
- [ ] UI 明确提示云端素材有保存期限，重要素材请及时保存。
