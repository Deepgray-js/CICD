# GitHub Actions + SSH + git pull CI/CD 部署方案
# test 06302
## 1. 目标

你要实现的是这样一条链路：

1. 本机修改代码
2. 本机执行 `git push`
3. GitHub 收到推送后自动触发 Actions
4. Actions 通过 SSH 登录服务器 `114.55.98.126`
5. 服务器进入项目目录执行 `git pull`
6. 拉取最新代码后安装依赖、构建项目、PM2 重启服务

这套方案的特点是：

- 不使用 Docker
- 不直接把本机文件“拷贝”到服务器
- 以 GitHub 仓库作为代码中转站
- 服务器通过 `git pull` 获取最新代码

一句话理解：
你的电脑负责 `push` 到 GitHub，GitHub Actions 负责“通知服务器更新”，服务器自己 `pull` 最新代码并重启服务。

## 2. 已生成文件

当前项目中已经生成了以下文件：

1. `.github/workflows/deploy.yml`
2. `scripts/deploy.sh`

它们的作用分别是：

- `deploy.yml`：监听 `main` 分支的 `push` 事件，SSH 登录服务器并执行部署脚本
- `deploy.sh`：在服务器上执行 `git pull`、安装依赖、构建项目、PM2 重载

## 3. 工作流说明

### 3.1 触发条件

当你本机执行下面命令时：

```bash
git add .
git commit -m "update"
git push origin main
```

GitHub 会自动执行：

```yaml
on:
  push:
    branches:
      - main
```

也就是说：

- 只有推送到 `main` 分支时才触发
- 如果你以后想改成 `master` 或 `release`，只要改工作流里的分支名即可

### 3.2 Actions 做了什么

工作流核心逻辑如下：

1. 使用 `appleboy/ssh-action`
2. SSH 登录你的服务器
3. 如果服务器上还没有这个仓库，就先 `git clone`
4. 如果仓库已经存在，就进入项目目录执行 `scripts/deploy.sh`

## 4. 服务器端脚本做了什么

`scripts/deploy.sh` 的逻辑是：

1. 进入部署目录 `/opt/cicd-app`
2. 切到 `main` 分支
3. 执行 `git pull origin main`
4. 如果有 `package-lock.json`，执行 `npm ci`
5. 没有锁文件则执行 `npm install`
6. 执行 `npm run build --if-present`
7. 用 PM2 重载或启动服务
8. 执行 `pm2 save`

这说明它默认更适合 Node.js 项目。

如果你的项目不是 Node.js 项目，而是 Java、Python、Go，也可以继续沿用这套 CI/CD 思路，只需要把 `deploy.sh` 里“依赖安装、构建、启动”的命令替换掉即可。

## 5. 你现在必须配置的 GitHub Secrets

进入 GitHub 仓库：

`Settings -> Secrets and variables -> Actions`

至少添加下面 4 个 Secrets：

### 5.1 `SERVER_HOST`

填服务器公网 IP：

```text
114.55.98.126
```

### 5.2 `SERVER_PORT`

如果你服务器 SSH 是默认端口，就填：

```text
22
```

### 5.3 `SERVER_USER`

填你登录服务器用的用户名，例如：

```text
root
```

或者：

```text
deploy
```

建议生产环境使用单独的部署用户，不建议一直直接用 root。

### 5.4 `SERVER_SSH_KEY`

这里填的是“GitHub Actions 用来登录服务器”的私钥内容。

注意：

- 这是服务器登录私钥
- 不是 GitHub 仓库的 token
- 一般是本地或 GitHub 专门生成的一对 SSH 密钥中的私钥

## 6. 服务器首次初始化

下面是首次部署前，你要在服务器上做的准备工作。

### 6.1 安装基础环境

登录服务器：

```bash
ssh root@114.55.98.126
```

安装基础工具：

```bash
apt update
apt install -y git curl
```

如果你的系统是 CentOS：

```bash
yum install -y git curl
```

安装 Node.js 和 npm。

如果你还没装 Node.js，建议使用 LTS 版本。

安装 PM2：

```bash
npm install -g pm2
```

### 6.2 创建部署目录

```bash
mkdir -p /opt/cicd-app
```

### 6.3 让服务器有权限从 GitHub 拉代码

这一点非常关键。

因为你的方案是“服务器执行 `git pull`”，所以服务器必须自己有权限读取 GitHub 仓库。

最推荐的方法是：

1. 在服务器上生成一对新的 SSH 密钥
2. 把公钥添加到 GitHub 仓库的 Deploy Key
3. 服务器使用这把私钥去 `git clone` / `git pull`

在服务器执行：

```bash
ssh-keygen -t ed25519 -C "github-deploy-key" -f ~/.ssh/id_ed25519_github
```

查看公钥：

```bash
cat ~/.ssh/id_ed25519_github.pub
```

把输出内容复制到 GitHub：

`Settings -> Deploy keys -> Add deploy key`

建议：

- Title：`server-deploy-key`
- 勾选只读权限即可

然后配置 SSH：

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
```

首次建立 GitHub 指纹信任：

```bash
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

测试是否能访问 GitHub：

```bash
ssh -T git@github.com
```

如果看到类似 “successfully authenticated” 的提示，说明服务器可以拉代码了。

### 6.4 首次手动 clone

如果是第一次上线，建议你先在服务器手动拉一次仓库，确认权限无误：

```bash
git clone -b main git@github.com:你的GitHub用户名/你的仓库名.git /opt/cicd-app
```

然后进入目录：

```bash
cd /opt/cicd-app
```

## 7. GitHub Actions 登录服务器的 SSH 密钥准备

这里要注意，你整个流程里有两套 SSH 权限，很多初学者最容易在这里混淆。

### 第一套：GitHub Actions -> 服务器

作用：
让 GitHub Actions 能 SSH 登录你的服务器。

你需要准备：

- 私钥放到 GitHub Secret：`SERVER_SSH_KEY`
- 对应公钥放到服务器用户的 `~/.ssh/authorized_keys`

如果你还没有这套密钥，可以在本地生成：

```bash
ssh-keygen -t ed25519 -C "github-actions-to-server"
```

然后：

1. 把私钥内容复制到 GitHub Secret `SERVER_SSH_KEY`
2. 把公钥追加到服务器的 `~/.ssh/authorized_keys`

### 第二套：服务器 -> GitHub

作用：
让服务器自己能 `git pull` GitHub 仓库。

你需要准备：

- 私钥放在服务器 `~/.ssh/id_ed25519_github`
- 公钥配置到 GitHub 仓库的 Deploy Key

记住一句话：

- GitHub Actions 想“进服务器”，要一把钥匙
- 服务器想“拉 GitHub 代码”，还要另一把钥匙

## 8. PM2 首次启动建议

如果你的项目已经有 `package.json` 且包含：

```json
{
  "scripts": {
    "start": "node app.js"
  }
}
```

那么当前 `deploy.sh` 会在第一次部署时执行：

```bash
pm2 start npm --name cicd-app -- start
```

如果你项目更复杂，建议你补一个 `ecosystem.config.js`，这样 PM2 管理会更稳定。

例如：

```js
module.exports = {
  apps: [
    {
      name: "cicd-app",
      script: "npm",
      args: "start",
      cwd: "/opt/cicd-app",
      env: {
        NODE_ENV: "production"
      }
    }
  ]
};
```

有了这个文件后，部署脚本会优先执行：

```bash
pm2 startOrReload ecosystem.config.js --env production
```

## 9. 标准上线流程

第一次准备完成后，后续你的操作会非常简单。

本机开发完成后执行：

```bash
git add .
git commit -m "feat: update project"
git push origin main
```

然后 GitHub 自动做这几件事：

1. 触发 Actions
2. SSH 登录服务器
3. 服务器执行 `git pull`
4. 安装依赖
5. 构建项目
6. PM2 重启

你只要去 GitHub 仓库的 `Actions` 页面看执行日志即可。

## 10. 常见问题排查

### 10.1 GitHub Actions 无法 SSH 登录服务器

表现：

- `ssh: handshake failed`
- `permission denied`

排查方向：

1. 检查 `SERVER_HOST`、`SERVER_PORT`、`SERVER_USER` 是否写对
2. 检查 `SERVER_SSH_KEY` 是否是完整私钥内容
3. 检查对应公钥是否已加入服务器 `authorized_keys`
4. 检查服务器安全组是否开放 22 端口
5. 检查服务器 SSH 服务是否正常运行

### 10.2 Actions 能连服务器，但服务器 `git pull` 失败

表现：

- `Permission denied (publickey)`
- `Repository not found`

排查方向：

1. 检查服务器是否已经配置 GitHub Deploy Key
2. 检查 `~/.ssh/config` 是否指定了正确的私钥
3. 检查仓库地址是否是 `git@github.com:用户名/仓库名.git`
4. 手动在服务器执行 `ssh -T git@github.com`
5. 手动在服务器执行 `git pull origin main`

### 10.3 `npm ci` 失败

表现：

- 锁文件不一致
- 依赖解析失败

排查方向：

1. 确认仓库里存在 `package-lock.json`
2. 如果依赖变化较大，可以先手动执行一次 `npm install`
3. 必要时把脚本里的 `npm ci` 改成统一 `npm install`

### 10.4 PM2 重启失败

表现：

- `script not found`
- `npm ERR! missing script: start`

排查方向：

1. 检查 `package.json` 里是否有 `start` 脚本
2. 如果启动命令不是 `npm start`，请修改 `deploy.sh`
3. 推荐提供 `ecosystem.config.js`

### 10.5 `git pull` 时有本地修改冲突

表现：

- 提示 working tree not clean

原因：

说明服务器项目目录里有手工改动，导致拉取冲突。

建议：

1. 服务器不要手工改生产代码
2. 所有改动都从本地提交到 GitHub
3. 生产服务器只负责 `pull` 和运行

## 11. 这套方案的优缺点

### 优点

- 上手快，适合个人项目和中小项目
- 不需要 Docker
- 思路清晰，容易排错
- 服务器上保留完整 Git 仓库，回滚方便

### 缺点

- 服务器必须保存仓库权限
- 部署环境一致性不如 Docker
- 如果依赖和系统环境复杂，后期维护成本会提高

## 12. 下一步你最应该做的事

请按下面顺序执行：

1. 把代码推送到 GitHub 仓库
2. 在 GitHub 配置 4 个 Actions Secrets
3. 在服务器配置“服务器 -> GitHub”的 Deploy Key
4. 在服务器安装 Node.js、npm、pm2、git
5. 确保 `/opt/cicd-app` 可用
6. 首次手动 clone 仓库测试
7. 本机执行一次 `git push origin main`
8. 去 GitHub Actions 页面观察部署日志

## 13. 你后面大概率还要改的两个地方

### 13.1 仓库地址

首次手动 clone 时，请把下面这个地址替换成你自己的：

```bash
git@github.com:你的GitHub用户名/你的仓库名.git
```

### 13.2 启动命令

如果你的项目不是 `npm start` 启动，请修改 `scripts/deploy.sh` 的 PM2 启动部分。

例如：

- 前端静态项目：可能不需要 PM2，而是重新构建后交给 Nginx
- Node API 项目：一般用 PM2
- Python 项目：要改成 `pip install` 和 `systemctl restart`

## 14. 结论

你的目标方案已经可以落地，核心链路就是：

```text
本机 git push
-> GitHub Actions 触发
-> SSH 登录服务器 114.55.98.126
-> 服务器 git pull
-> 安装依赖
-> 构建项目
-> PM2 重启
```

如果你下一步愿意，我可以继续帮你做两件事中的任意一件：

1. 按你的真实 GitHub 仓库名，把文档中的仓库地址和工作流变量全部替换成最终版本
2. 根据你的项目类型（前端 / Node 后端 / Python / Java），把 `deploy.sh` 改成完全匹配你项目的生产部署脚本
