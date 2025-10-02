# Pangolin を AWS Lightsail (IPv6-only) に Terraform + GitHub Actions でデプロイ（日本語）

このリポジトリは、**ローカルに Terraform を入れずに**、**GitHub Actions だけで** Pangolin を AWS Lightsail にデプロイするテンプレートです。  
Terraform の **State は S3**、**Lock は DynamoDB** で管理し、**PR で plan / main で apply** が自動実行されます。

- OS: **Amazon Linux 2023**
- ネットワーク: **IPv6-only**（パブリック IPv4 なし）
- プロビジョニング: Terraform（Lightsail + 公開ポート設定 + /opt/pangolin に公式インストーラ配置）
- 構成管理: GitHub Actions（S3/DynamoDB が無ければ **自動作成**）
- 初期化: インスタンスに SSH → `sudo ./installer`（Pangolin 公式の対話インストーラ）

---

## ディレクトリ構成

```
.
├── infra/
│   ├── main.tf            # Lightsail (AL2023 / IPv6-only) とポート開放、cloud-init
│   ├── variables.tf       # 変数（リージョンやドメイン等）
│   ├── outputs.tf         # 出力（IPv6, SSH例, ダッシュボードURL）
│   ├── versions.tf        # Terraform / Provider バージョン
│   └── backend.tf         # S3/DynamoDB バックエンド（値は Actions で流し込み）
└── .github/
    └── workflows/
        └── terraform.yml  # CI: PRでplan / CD: mainでapply（S3/DDBを自動作成）
```

---

## 事前準備（最初の一度だけ）

### 1) GitHub Actions の **Variables** を設定
GitHub リポジトリ → **Settings → Secrets and variables → Actions → Variables** に以下を追加します。

| 変数名 | 例 | 説明 |
|---|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/GitHubActions-Terraform` | GitHub OIDC から引き受ける IAM ロール ARN |
| `AWS_REGION` | `ap-northeast-1` | AWS リージョン |
| `TF_BACKEND_BUCKET` | `tfstate-azunyan-io` | Terraform State 用 S3 バケット名（グローバル一意） |
| `TF_BACKEND_TABLE` | `tf-locks-azunyan-io` | Lock 用 DynamoDB テーブル名 |
| `TF_BACKEND_KEY` | `lightsail/pangolin/terraform.tfstate` | State のキー（パス） |

> Secrets は不要です（**OIDC** を使用）。Access Key は使いません。

### 2) AWS 側：OIDC ロール（信頼ポリシー & 権限）
- **アイデンティティプロバイダ**：`token.actions.githubusercontent.com` を OIDC で登録
- **信頼ポリシー（例）**：
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:ref:refs/heads/*"
        }
      }
    }]
  }
  ```
- **権限ポリシー（例）**：Lightsail の操作、S3 バケット/オブジェクト、DynamoDB の作成およびロック操作。運用後は最小権限に絞ってください。

---

## 変数（`infra/variables.tf`）

| 変数名 | 既定値 | 用途 |
|---|---|---|
| `region` | `ap-northeast-1` | AWS リージョン |
| `bundle_id` | `nano_3_0` | Lightsail 最安相当バンドル（地域/時期で変わる場合あり） |
| `blueprint_id` | `amazon_linux_2023` | Amazon Linux 2023 のブループリント |
| `availability_zone` | `ap-northeast-1a` | AZ |
| `instance_name` | `pangolin-ipv6` | インスタンス名 |
| `dashboard_domain` | `pangolin.azunyan.io` | ダッシュボード FQDN（後で AAAA をこの IPv6 へ） |

---

## 使い方：PR で **plan** / main で **apply**

### 1) PR を作成（plan）
```bash
git checkout -b feat/update
# 例: infra/*.tf を編集
git add .
git commit -m "update"
git push origin feat/update
```
- GitHub で Pull Request（`feat/update` → `main`）を作成すると、Actions の **plan ジョブ**が自動実行されます。
- 最初の実行時、S3 バケット と DynamoDB テーブルが **存在しなければ作成** されます。
- `terraform init` → `fmt` → `validate` → `plan` が実行され、差分がログに表示されます。

### 2) main にマージ（apply）
- PR を `main` にマージ（または `main` に直接 push）。
- Actions の **apply ジョブ**が自動で走り、`terraform apply -auto-approve` まで実行されます。

---

## デプロイ後の作業（Pangolin 初期化）

1. **IPv6 アドレスの確認**：  
   - Lightsail コンソールで該当インスタンスの **IPv6** を確認  
   - もしくは Actions の `terraform apply` の実行ログ（オプションで `terraform output` ステップを追加すると便利）

2. **DNS（AAAA）設定**：  
   `dashboard_domain`（既定：`pangolin.azunyan.io`）の **AAAA レコード**を、上記の IPv6 に向ける。

3. **SSH で接続**：
   ```bash
   ssh ec2-user@[<IPv6アドレス>]
   ```

4. **Pangolin 公式インストーラを実行**：
   ```bash
   cd /opt/pangolin
   sudo ./installer
   ```
   対話に従って **Base Domain**（例：`azunyan.io`）や **Dashboard Domain**（例：`pangolin.azunyan.io`）、メールアドレス等を入力。

5. **ブラウザで初期セットアップ**：  
   `https://pangolin.azunyan.io/auth/initial-setup` にアクセス。

---

## よくある質問 / トラブルシューティング

- **`Unterminated template string` が出る**  
  - `user_data = <<-CLOUDINIT` の **終端行 `CLOUDINIT`** を入れ忘れていないか確認してください。
  - さらに、heredoc 内で `${...}` を文字通り書くと Terraform の式と解釈されます。必要な場合は **`$${...}`** とエスケープします。

- **OIDC で `AssumeRole` 失敗**  
  - 信頼ポリシーの `sub` が `repo:<OWNER>/<REPO>:ref:refs/heads/*` を許可しているか、Workflow で `permissions: id-token: write` があるか確認。

- **S3 バケット名が衝突**  
  - S3 のバケット名はグローバルで一意です。`TF_BACKEND_BUCKET` を別名に変更してください。

- **DynamoDB のロックが残り Apply できない**  
  - まれに中断後に Lock が残ることがあります。`TF_BACKEND_TABLE` のテーブルから該当アイテムを手動削除してください。

- **IPv6-only で外部に繋がらない**  
  - IPv4 到達性はありません。外部ダウンロード先（レジストリ/サイト）が **IPv6 対応**していることを確認してください。

---

## オプション：Apply の最後に Outputs を表示したい
`terraform.yml` の apply ジョブ末尾に次のステップを追加すると、アドレスや URL をログで確認しやすくなります。

```yaml
      - name: Terraform Output
        run: terraform output
```

---

## カスタマイズのヒント

- **環境分離**：`TF_BACKEND_KEY` をブランチや環境名で切り替える（例：`lightsail/dev/...` / `lightsail/prod/...`）。
- **静的解析**：`tflint` / `tfsec` を plan の前に実行。
- **Plan 結果を PR コメント**：`actions/github-script` などで要約を自動コメント。

---

## ライセンス
このテンプレートは自由にご活用ください。

---

### 連絡先
不明点や追加要望（Outputs の表示、環境分離、最小権限の IAM ポリシー化など）があれば Issue/PR でお知らせください。
