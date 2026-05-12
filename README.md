# 每天更新 geo 数据包

该项目通过 GitHub Actions 定时下载 geo 数据和规则文件，打包为 `geo.zip` 后发布到 GitHub Release，并同步上传到 Cloudflare 对应服务器。

## 描述

工作流会下载并打包以下文件：

- `geoip.dat`
- `geosite.dat`
- `domain.txt`，来自 `neodevpro/neodevhost`
- `mosdns_adrules.txt`
- `AWAvenue-Ads-Rule-Mosdns_v5.txt`
- `all_cn.txt`
- `all_cn_ipv6.txt`
- `cloudflare-cidr.txt`，来自 Cloudflare IPs API

打包产物为 `geo.zip`，会作为 Release 资产上传。

## Cloudflare 同步

`geo.zip` 打包完成后，工作流会通过 `curl` 使用 `PUT` 请求同步到 Cloudflare 对应服务器。上传请求会携带自定义请求头：

```bash
X-CI-Upload-Token: ${CI_UPLOAD_TOKEN}
```

需要在 GitHub Repository Secrets 中配置以下变量：

- `CLOUDFLARE_SITE_USER`
- `CLOUDFLARE_SITE_PASS`
- `CLOUDFLARE_MANAGE_URL`
- `CLOUDFLARE_MANAGE_PASS`
- `CI_UPLOAD_TOKEN`

`CI_UPLOAD_TOKEN` 是自定义共享密钥，可使用以下命令生成：

```bash
openssl rand -hex 32
```

Cloudflare 自定义规则需要匹配上传请求的域名、方法、路径和请求头，例如：

```text
(http.host eq "你的上传域名"
 and http.request.method eq "PUT"
 and starts_with(http.request.uri.path, "/你的上传路径")
 and any(http.request.headers["x-ci-upload-token"][*] eq "你的 CI_UPLOAD_TOKEN"))
```

规则措施选择 `跳过`，并按需跳过 WAF 托管规则、浏览器完整性检查、安全级别和自动程序攻击模式相关规则。若 Cloudflare 仍返回 `Just a moment...` 或 `403`，需要关闭对应域名的自动程序攻击模式 / JS 检测，或改用专门的灰云上传子域名。

### 文件过期时间

上传请求中的 `e` 参数用于设置本次更新后的文件过期时间。当前工作流使用：

```bash
-F "e=never"
```

定时触发时默认使用 `never`，即本次 `PUT` 覆盖后将文件设置为永不过期。手动触发工作流时，可以通过 `expiration` 选项选择过期时间。

可选值包括：

- `never`：永不过期
- `300`：300 秒
- `30m`：30 分钟
- `2h`：2 小时
- `7d`：7 天
- `default`：不传 `e` 参数，使用服务端 `DEFAULT_EXPIRATION`

使用 `e=never` 时，服务端需要开启：

```text
ALLOW_PERMANENT_PASTES=true
```

否则服务端会返回 `400`。

如果选择 `default`，工作流不会传 `e` 参数；服务端会按 `DEFAULT_EXPIRATION` 从本次更新时间起重新计算过期时间。

更新并设置 7 天过期：

```bash
command curl -v -# \
  --url "$MANAGE_URL_FULL" \
  -u "${SITE_USER}:${SITE_PASS}" \
  -X PUT \
  -F "c=@/tmp/geo.zip" \
  -F "e=7d"
```

更新并保持永不过期：

```bash
command curl -v -# \
  --url "$MANAGE_URL_FULL" \
  -u "${SITE_USER}:${SITE_PASS}" \
  -X PUT \
  -F "c=@/tmp/geo.zip" \
  -F "e=never"
```

### 更新说明

工作流每天定时运行，也支持手动触发。每次运行会生成新的 Release，并上传最新的 `geo.zip`。
