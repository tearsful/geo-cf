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

GitHub Release 还会单独附带 `cn_ip_cidr.rsc`（MikroTik 导入脚本，不包含在 `geo.zip` 内）。

打包产物为 `geo.zip`，会作为 Release 资产上传到本仓库（`geo-cf`）。

另会将 `mikrotik_cn_ipv4.txt`、`mikrotik_cn_ipv6.txt` 同步到公共仓库 [tearsful/geo](https://github.com/tearsful/geo) 的 **`latest` Release**（不存在则创建；每次覆盖同名资产；并删除该仓库内除 `latest` 外的其它 Release，只保留一份）。

### 公共仓库 `latest` Release 同步配置

工作流用 PAT 调用 `gh` 写入 **另一个仓库**（由变量 `TEARSFUL_GEO_REPO` 指定）。`GITHUB_TOKEN` 只能操作当前 `geo-cf` 仓库，不能代替此 PAT。

**1. 在 GitHub 账号里创建 Token（不是在仓库里“生成”）**

- 打开：**GitHub 右上角头像 → Settings → Developer settings → Personal access tokens**
- **Fine-grained（推荐）**：新建 token，Repository access 选 **Only select repositories** 并勾选 `tearsful/geo`（或你在 `TEARSFUL_GEO_REPO` 里填的仓库）；Permissions → **Contents** 设为 **Read and write**。
- **Classic**：勾选 `repo`（或至少能向目标仓库发 Release 的权限）。

创建完成后**只显示一次**的 token 字符串先复制保存。

**2. 把 Token 填进 geo-cf 仓库的 Secret（只是存放，不是在这里创建）**

- 打开 **geo-cf** 仓库：**Settings → Secrets and variables → Actions → Secrets → New repository secret**
- Name：`TEARSFUL_GEO_RELEASE_TOKEN`
- Secret：粘贴上一步复制的 PAT

**3. 配置目标仓库 `owner/repo`（二选一，不要留空）**

- **Variables（推荐）**：Name `TEARSFUL_GEO_REPO`，Value 如 `tearsful/geo`
- **或 Secrets**：Name `TEARSFUL_GEO_REPO`，Value 同样填 `tearsful/geo`（若你习惯两个都建在 Secrets 里也可以）

工作流会优先读 Variable，没有时再读同名 Secret。

**若 Publish 步骤出现 `403` / `Resource not accessible by personal access token`**

说明 PAT **看不到或不能写** `TEARSFUL_GEO_REPO` 指向的仓库（常见：Fine-grained 只勾了 `geo-cf`，没勾 `tearsful/geo`；或 **Contents 仍是 Read-only**）。

请重新编辑或新建 Token（账号 **Settings → Developer settings → Personal access tokens**）：

| 类型 | 必做 |
|------|------|
| **Fine-grained** | Repository access → **Only select repositories** → 勾选 **`tearsful/geo`**（与 Secret 里 `TEARSFUL_GEO_REPO` 一致）；Permissions → **Contents → Read and write**；**Metadata** 保持 Read（默认即可）。 |
| **Classic** | 勾选 **`repo`**（私有库）或至少 **`public_repo`**（仅公开库且只需写 Release 时有时不够，建议直接 `repo`）。 |

保存后把**新 token 字符串**更新到 geo-cf 的 Secret **`TEARSFUL_GEO_RELEASE_TOKEN`**（改权限不会自动刷新旧 Secret）。若目标库在组织下且启用 SSO，还需在 Token 列表里对该 token 点 **Configure SSO → Authorize**。

本地自测（将 `YOUR_PAT` 换成新 token）：

```bash
curl -sS -H "Authorization: Bearer YOUR_PAT" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/tearsful/geo | jq '{full_name, permissions}'
```

应看到 `"push": true`，且 `POST` 创建 Release 不再返回 403。

## PVE 本地生成 `cn_ip_cidr.rsc`

在 Proxmox VE 宿主机或 LXC/虚拟机中，可用仓库脚本本地生成与 GitHub Actions 相同逻辑的 MikroTik 脚本，无需跑完整工作流。

脚本路径：仓库根目录 `generate-cn-ip-cidr-rsc.sh`

生成文件（每次执行都会**覆盖**已有的 `cn_ip_cidr.rsc`）：

- 下载过程在临时目录完成，校验通过后再写入目标路径
- 成功后**不会保留** `all_cn.txt` / `all_cn_ipv6.txt`；脚本会在开始与结束时删除 `OUTPUT_DIR` 内这两类中间文件（含旧版脚本遗留）

### 依赖

PVE 基于 Debian，一般已带 `wget`；若没有：

```bash
apt update
apt install -y wget curl git
```

### 获取代码

```bash
git clone https://github.com/tearsful/geo-cf.git /opt/geo-cf
cd /opt/geo-cf
chmod +x generate-cn-ip-cidr-rsc.sh
```

仅更新脚本时：

```bash
cd /opt/geo-cf && git pull
```

### 手动执行

默认输出到当前目录下的 `./output/mikrotik/`：

```bash
cd /opt/geo-cf
./generate-cn-ip-cidr-rsc.sh
ls -la output/mikrotik/cn_ip_cidr.rsc
```

指定输出目录（推荐固定路径，便于 cron 与后续拷贝到 RouterOS）：

```bash
OUT_DIR=/var/lib/mikrotik-cn ./generate-cn-ip-cidr-rsc.sh
# 或
./generate-cn-ip-cidr-rsc.sh /var/lib/mikrotik-cn
```

自定义 `.rsc` 路径：

```bash
OUT_DIR=/var/lib/mikrotik-cn \
RSC_PATH=/var/lib/mikrotik-cn/cn_ip_cidr.rsc \
./generate-cn-ip-cidr-rsc.sh
```

成功结束时脚本会打印三个文件路径及 `cn_ip_cidr.rsc` 字节大小。

### 定时任务（cron）

编辑 root 或运行用户的 crontab，例如每天 08:20（时区以 PVE 系统为准）：

```bash
crontab -e
```

```cron
20 8 * * * /opt/geo-cf/generate-cn-ip-cidr-rsc.sh /var/lib/mikrotik-cn >> /var/log/cn-ip-cidr.log 2>&1
```

首次建议手动跑一遍并查看日志：

```bash
/var/lib/mikrotik-cn/cn_ip_cidr.rsc
tail -20 /var/log/cn-ip-cidr.log
```

### 在 MikroTik 上使用

将 `cn_ip_cidr.rsc` 上传到 RouterOS（Winbox / SFTP / `/tool fetch` 等），在终端执行：

```text
/import file-name=cn_ip_cidr.rsc
```

IPv6 段脚本内已用 `:if ([:len [/ipv6 dhcp-cl find where status=bound]] > 0)` 包裹，无 IPv6 DHCP 客户端的节点不会写入 IPv6 列表。

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

## 更新说明

| 工作流 | 定时（北京时间） | 说明 |
|--------|------------------|------|
| Scheduled Geo Data Update | 每天 **10:00** | 下载、打包、上传 Cloudflare、发 Release |
| Delete Old Workflows | 每天 **10:05** | 删除超过 **1 天**的 Actions 运行记录；Release 仅保留最新 1 个 |

GitHub `schedule` 使用 **UTC**；上表时间为 UTC+8，无夏令时。界面里 **手动 Run workflow** 的运行时间不会落在上述整点，只有 `schedule` 触发才对齐定时。

清理 Actions 历史需要 workflow 内声明 `permissions: actions: write`（见 `Delete Old.yml`）。若仓库 **Settings → Actions → General → Workflow permissions** 为「Read」且组织策略禁止提升权限，需在仓库改为 **Read and write**，或改用具备 `actions: write` 的 PAT。

工作流也支持手动触发。每次数据更新运行会生成新的 Release，并上传最新的 `geo.zip` 与 `cn_ip_cidr.rsc`。
