# dxvk-tools-install-script

本仓库提供**我自制的** [DXVK](https://github.com/doitsujin/dxvk)、[DXVK-NVAPI](https://github.com/jp7677/dxvk-nvapi)、[VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton) 安装脚本。

DXVK 和 DXVK-VKD3D 的官方仓库在各自的最新发布版本中移除了附带的安装脚本。虽然他们提供了另一种安装/卸载的方式，但这对我造成了不便。因此便有了这个仓库。

本仓库提供的脚本，不仅具备原官方安装脚本的功能，还拥有一些小优势：

-   脚本的提示和帮助信息使用中文
-   确保 Wine 的几个关键命令 `wine`、`wine64`、`wineserver` 属于同一个 Wine 安装
-   所有的 Wine 内部命令（例如 `regsvr32`、`reg`、`wineboot` 等）都使用 `wine[64]` 调用
    -   为什么要这样？想象一下 `winepath` 和 `wineboot` 都在 PATH 里但是两个命令实际所属的 Wine 安装不同（甚至其中一个不存在）的状况吧，原官方脚本无法避免在这种情况下产生错误
-   使用（我个人认为）更有效的 WINEPREFIX 架构检测方式

_**不要过于信赖我的脚本。它可能会在某些情况下出错，在最严重的情况下，你用来安装的 `WINEPREFIX` 会出现严重问题。如果你碰到了这样的问题，请去提交 Issue。**_

## 使用

1. 无论你要安装什么，先去下载一个，本仓库不提供你要安装的组件。

-   [下载 DXVK](https://github.com/doitsujin/dxvk/releases/latest)
-   [下载 DXVK-NVAPI](https://github.com/jp7677/dxvk-nvapi/releases/latest)
-   [下载 VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton/release/latest)

2. 解压你在上一步下载的文件。例如，你下载的是 `dxvk-2.1.tar.gz`，应该解压出一个目录 `dxvk-2.1`。
3. 把本仓库中对应的安装脚本拷贝到上一步解压出的目录，并赋予可执行权限：`chmod u+x setup-dxvk.sh`。
4. 安装或卸载。下面有示例。

示例（以 `setup-dxvk.sh` 为例）：

-   安装
    ```sh-session
    $ > WINEPREFIX=/path/to/winepfx ./setup-dxvk.sh install
    ```
-   卸载
    ```sh-session
    $ > WINEPREFIX=/path/to/winepfx ./setup-dxvk.sh uninstall
    ```

以上示例对于其余两个脚本 `setup-dxvk-nvapi.sh` 和 `setup-vkd3d-proton.sh` 同样适用。

每次安装时都会向 `WINEPREFIX` 复制组件内的文件。如果你不想让它复制文件，添加 `--symlink` 参数。该参数不影响卸载。
