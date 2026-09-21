# MyKit

Mac 菜单栏小工具箱。目前的功能：**剪切板历史** —— 双击 Option 呼出，保留最近 7 天复制过的文字，可搜索，回车直接粘贴。

## 安装

在"终端"里进入本目录，依次运行：

```bash
scripts/create-dev-cert.sh   # 只需要运行一次
scripts/build-app.sh
scripts/install.sh
```

完成后屏幕右上角会出现 MyKit 图标（三层叠起来的方块）。

## 第一次使用：授权

第一次启动会弹出引导窗口：

1. 点「打开系统设置」
2. 在「辅助功能」列表里找到 MyKit，打开右边的开关
3. 引导窗口会自动关闭，授权完成

如果右上角图标变成 ⚠️ 三角形，说明授权丢失了，按上面的步骤重新打开开关即可。

## 怎么用

| 操作 | 效果 |
|---|---|
| 快速按两下 Option | 打开 / 关闭剪切板面板 |
| 直接打字 | 搜索 |
| ↑ ↓ | 选择 |
| 回车 | 粘贴到刚才正在用的 App |
| ⌘1 – ⌘9 | 直接粘贴第 1–9 条 |
| ⌘⌫ | 删除选中的记录 |
| Esc 或点击面板外 | 关闭面板 |

## 退出

**左键或右键**点击右上角的 MyKit 图标 →「退出 MyKit」。

同一个菜单里还有：打开剪切板、暂停记录、偏好设置（保留天数、开机自启、清空历史）。

## 数据在哪里

`~/Library/Application Support/MyKit/clipboard.sqlite`，只保存在本机，不联网。从密码管理器复制的密码不会被记录。

## 更新

改了代码之后重新运行 `scripts/build-app.sh && scripts/install.sh`，不需要重新授权。

## 开发

```bash
scripts/test.sh                                   # 跑全部单元测试
scripts/test.sh --filter ClipboardStoreTests      # 只跑一组
```

设计文档：`docs/superpowers/specs/2026-09-21-mykit-clipboard-design.md`
