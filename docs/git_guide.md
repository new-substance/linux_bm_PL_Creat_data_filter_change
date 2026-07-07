# Git 操作简明手册

## 环境信息

- 仓库路径: `f:\HA_20260411_PC2\HA_20260506_Ps_xyb\HA_20260506_Ps_xyb`
- 远程仓库: `https://github.com/new-substance/linux_bm_PL_Creat_data_filter_change`
- 用户: `cf675227` / `1521249905@qq.com`

---

## 一、日常保存代码 (修改 → 暂存 → 提交 → 推送)

```bash
cd "f:\HA_20260411_PC2\HA_20260506_Ps_xyb\HA_20260506_Ps_xyb"

# 1. 查看改了哪些文件
git status

# 2. 查看具体改了什么
git diff

# 3. 暂存要保存的文件 (挑选改动)
git add <文件路径>
# 或者暂存所有改动:
git add -u

# 4. 提交 (本地保存一个版本快照)
git commit -m "描述你改了什么"

# 5. 推送到 GitHub (云端备份 + 协作)
git push
```

### 常用组合 (一键暂存+提交+推送)

```bash
git add -u && git commit -m "修复xxx问题" && git push
```

---

## 二、回退版本

### 场景 1: 还没 commit，想撤销对某个文件的修改

```bash
# 撤销工作区改动，恢复到上次 commit 的状态
git checkout -- <文件路径>

# 撤销所有改动
git checkout -- .
```

### 场景 2: 已经 git add 暂存了，想取消暂存

```bash
# 取消暂存 (保留工作区修改)
git reset HEAD <文件路径>

# 取消全部暂存
git reset HEAD .
```

### 场景 3: 已经 commit 了但还没 push

```bash
# 撤销最近一次 commit，改动回到暂存区 (最常用，最安全)
git reset --soft HEAD~1

# 撤销最近一次 commit，改动回到工作区 (取消暂存)
git reset HEAD~1

# 彻底丢弃最近一次 commit 的所有改动 (⚠ 不可恢复)
git reset --hard HEAD~1
```

### 场景 4: 已经 push 到 GitHub 了

```bash
# 方法A: 创建一个"反向"提交来抵消 (推荐，不影响别人)
git revert HEAD
git push

# 方法B: 强制回退 (⚠ 会改写历史，仅自己用)
git reset --hard HEAD~1
git push --force
```

### 场景 5: 回到之前某个特定版本

```bash
# 查看提交历史，找到目标版本号
git log --oneline

# 临时回到那个版本看看
git checkout <commit号>

# 回到最新版本
git checkout main

# 永久回退到某个版本 (⚠ 丢弃之后的所有改动)
git reset --hard <commit号>
```

---

## 三、当前仓库的提交历史

```
a394eed  Add C driver API for filter v2.1
7f0b25f  Initial: PL Creat_data testdata_Generate filter v2.1
```

要回退到初始版本:
```bash
git reset --hard 7f0b25f
```

---

## 四、常用速查

| 命令 | 作用 |
|------|------|
| `git status` | 查看当前状态 |
| `git diff` | 查看未暂存的改动 |
| `git log --oneline` | 查看提交历史 |
| `git checkout -- <文件>` | 撤销单个文件修改 |
| `git reset --soft HEAD~1` | 撤销最近 commit (保留改动) |
| `git reset --hard HEAD~1` | 丢弃最近 commit (不可恢复) |
| `git reflog` | 查看所有操作历史 (救命命令) |

> **救命原则**: `--hard` 操作前，先用 `git log` / `git reflog` 确认。只要 commit 过，`git reflog` 几乎总能找回来。
