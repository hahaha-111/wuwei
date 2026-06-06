import router from '@ohos.router';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';

import { MonitorPageParams } from '../viewmodel/MonitorViewModel';
import { FileUtil } from '../common/utils/FileUtil';

@Entry
@Component
struct RecordListPage {
  @State displayFiles: string[] = [];
  @State currentPath: string = '';

  // 传入参数
  deviceName: string = '';

  // 预览状态
  @State previewImagePath: string = '';
  @State isViewingText: boolean = false;
  @State textContent: string = '';
  @State viewingFileName: string = '';

  // ⭐ 新增：编辑模式状态
  @State isEditMode: boolean = false;
  @State selectedFiles: string[] = [];

  aboutToAppear() {
    const params = router.getParams() as MonitorPageParams;
    this.deviceName = params?.deviceName || '未知设备';

    const ctx = getContext(this) as common.UIAbilityContext;
    this.currentPath = `${ctx.filesDir}/无畏/${this.deviceName}`;

    if (!fs.accessSync(this.currentPath)) {
      try {
        fs.mkdirSync(this.currentPath, true);
      } catch (e) {}
    }

    this.refreshList();
  }

  refreshList() {
    this.displayFiles = [];
    // 刷新列表时，重置选择状态
    this.selectedFiles = [];
    if (!fs.accessSync(this.currentPath)) return;

    try {
      const list = fs.listFileSync(this.currentPath);
      // 过滤掉隐藏文件，并简单排序
      this.displayFiles = list.filter(f => !f.startsWith('.')).sort();
    } catch (e) {
      console.error('List file failed:', e);
    }
  }

  // ⭐ 新增：切换编辑模式
  toggleEditMode() {
    this.isEditMode = !this.isEditMode;
    this.selectedFiles = []; // 切换时清空选择
  }

  // ⭐ 新增：全选/取消全选
  toggleSelectAll() {
    if (this.selectedFiles.length === this.displayFiles.length) {
      this.selectedFiles = [];
    } else {
      this.selectedFiles = [...this.displayFiles];
    }
  }

  // ⭐ 新增：切换单个文件选择
  toggleFileSelection(fileName: string) {
    if (this.selectedFiles.includes(fileName)) {
      this.selectedFiles = this.selectedFiles.filter(f => f !== fileName);
    } else {
      this.selectedFiles.push(fileName);
    }
  }

  // ⭐ 新增：批量删除
  batchDelete() {
    if (this.selectedFiles.length === 0) return;

    promptAction.showDialog({
      title: '批量删除',
      message: `确定要删除选中的 ${this.selectedFiles.length} 个项目吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#E53935' }
      ]
    }).then((resp) => {
      if (resp.index === 1) {
        let deletedCount = 0;
        const ctx = getContext(this) as common.UIAbilityContext;

        this.selectedFiles.forEach(fileName => {
          const fullPath = `${this.currentPath}/${fileName}`;
          try {
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
              // 简单处理：尝试删除空文件夹
              fs.rmdirSync(fullPath);
            } else {
              fs.unlinkSync(fullPath);
            }
            deletedCount++;
          } catch (e) {
            console.error(`Delete ${fileName} failed:`, e);
          }
        });

        promptAction.showToast({ message: `已删除 ${deletedCount} 个项目` });
        this.toggleEditMode(); // 退出编辑模式
        this.refreshList();
      }
    });
  }

  // ⭐ 新增：批量分享
  batchShare() {
    // 过滤掉文件夹，只分享文件
    const filesToShare = this.selectedFiles.filter(f => f.indexOf('.') !== -1);

    if (filesToShare.length === 0) {
      promptAction.showToast({ message: '请选择文件进行分享' });
      return;
    }

    const context = getContext(this) as common.UIAbilityContext;

    try {
      // 构造第一个分享记录
      const firstFile = filesToShare[0];
      const firstPath = `${this.currentPath}/${firstFile}`;
      const firstUri = fileUri.getUriFromPath(firstPath);

      let type = 'general.file';
      if (firstFile.endsWith('.png')) type = 'general.image';
      else if (firstFile.endsWith('.txt') || firstFile.endsWith('.json')) type = 'general.plain-text';

      const shareData = new systemShare.SharedData({
        utd: type,
        uri: firstUri,
        title: '批量分享',
        content: `分享 ${filesToShare.length} 个文件`
      });

      // 添加剩余文件
      for (let i = 1; i < filesToShare.length; i++) {
        const fileName = filesToShare[i];
        const fullPath = `${this.currentPath}/${fileName}`;
        const uri = fileUri.getUriFromPath(fullPath);

        let fileType = 'general.file';
        if (fileName.endsWith('.png')) fileType = 'general.image';
        else if (fileName.endsWith('.txt') || fileName.endsWith('.json')) fileType = 'general.plain-text';

        shareData.addRecord({
          utd: fileType,
          uri: uri
        });
      }

      const controller = new systemShare.ShareController(shareData);
      controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.BATCH
      });

    } catch (e) {
      console.error('Batch share failed:', JSON.stringify(e));
      promptAction.showToast({ message: '分享调起失败: ' + (e as Error).message });
    }
  }

  // 单个删除（保留原有功能，但在编辑模式下不可用）
  deleteFile(fileName: string) {
    const fullPath = `${this.currentPath}/${fileName}`;
    promptAction.showDialog({
      title: '删除确认',
      message: `确定要永久删除文件 "${fileName}" 吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#E53935' }
      ]
    }).then((resp) => {
      if (resp.index === 1) {
        try {
          fs.unlinkSync(fullPath);
          promptAction.showToast({ message: '文件已删除' });
          if (this.previewImagePath === fullPath) this.previewImagePath = '';
          if (this.viewingFileName === fileName) this.isViewingText = false;
          this.refreshList();
        } catch (e) {
          promptAction.showToast({ message: '删除失败: ' + (e as Error).message });
        }
      }
    });
  }

  onItemClick(name: string) {
    // ⭐ 编辑模式下，点击项为选中/取消选中
    if (this.isEditMode) {
      this.toggleFileSelection(name);
      return;
    }

    const fullPath = `${this.currentPath}/${name}`;
    try {
      const stat = fs.statSync(fullPath);

      if (stat.isDirectory()) {
        this.currentPath = fullPath;
        this.refreshList();
      } else {
        if (name.endsWith('.json')) {
          this.playVideo(fullPath);
        } else if (name.endsWith('.png')) {
          this.previewImagePath = fullPath;
        } else if (name.endsWith('.csv') || name.endsWith('.txt')) {
          this.viewingFileName = name;
          this.textContent = this.readTextFile(fullPath);
          this.isViewingText = true;
        }
      }
    } catch (e) {
      console.error('File stat failed:', e);
    }
  }

  playVideo(path: string) {
    const params: MonitorPageParams = {
      deviceName: this.deviceName,
      playbackMode: true,
      playbackFilePath: path
    };
    let navParams: MonitorPageParams = {
      deviceName: this.deviceName,
      playbackMode: true,
      playbackFilePath: path
    };
    router.pushUrl({
      url: 'pages/MonitorPage',
      params: navParams
    });
  }

  readTextFile(path: string): string {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const decoder = new util.TextDecoder();
      return decoder.decodeWithStream(new Uint8Array(buf));
    } catch (e) {
      return '读取文件失败: ' + (e as Error).message;
    }
  }

  shareFile(fileName: string) {
    const fullPath = `${this.currentPath}/${fileName}`;
    const context = getContext(this) as common.UIAbilityContext;

    try {
      const uri = fileUri.getUriFromPath(fullPath);
      let type = 'general.file';
      if (fileName.endsWith('.png')) type = 'general.image';
      else if (fileName.endsWith('.json') || fileName.endsWith('.txt')) type = 'general.plain-text';

      const shareData = new systemShare.SharedData({
        utd: type,
        uri: uri,
        title: fileName,
        content: `分享文件: ${fileName}`
      });

      const controller = new systemShare.ShareController(shareData);
      controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });

    } catch (e) {
      try {
        promptAction.showToast({ message: '分享失败: ' + (e as Error).message });
      } catch(ignore){}
    }
  }

  build() {
    Stack() {
      // 1. 主文件列表
      Column() {
        // 顶部导航
        Row() {
          Button('< 返回')
            .onClick(() => {
              const ctx = getContext(this) as common.UIAbilityContext;
              const root = `${ctx.filesDir}/无畏/${this.deviceName}`;

              // 如果在编辑模式，优先退出编辑模式
              if (this.isEditMode) {
                this.toggleEditMode();
                return;
              }

              if (this.currentPath.length > root.length) {
                const idx = this.currentPath.lastIndexOf('/');
                this.currentPath = this.currentPath.substring(0, idx);
                this.refreshList();
              } else {
                router.back();
              }
            })
            .backgroundColor(Color.Transparent)
            .fontColor('#333')

          Text('文件管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .margin({left: 10})

          Blank()

          // ⭐ 新增：管理按钮
          Button(this.isEditMode ? '取消' : '管理')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .fontColor('#1976D2')
            .onClick(() => {
              this.toggleEditMode();
            })
        }
        .height(50)
        .width('100%')
        .backgroundColor('#F5F5F5')
        .padding({left: 10, right: 10})

        Text(this.currentPath.split('/').pop() || '根目录')
          .fontSize(12)
          .fontColor('#666')
          .padding(8)
          .width('100%')
          .backgroundColor('#FAFAFA')

        List() {
          if (this.displayFiles.length === 0) {
            ListItem() {
              Text('暂无文件').fontSize(14).fontColor('#999').width('100%').textAlign(TextAlign.Center).padding(20)
            }
          }

          ForEach(this.displayFiles, (item: string) => {
            ListItem() {
              Row() {
                // ⭐ 编辑模式：显示复选框
                if (this.isEditMode) {
                  Checkbox()
                    .select(this.selectedFiles.includes(item))
                    .onChange(() => {
                      this.toggleFileSelection(item);
                    })
                    .margin({ right: 10 })
                }

                Text(item.endsWith('.json') ? '📹' : (item.endsWith('.png') ? '🖼️' : (item.endsWith('.csv')||item.endsWith('.txt') ? '📄' : '📁')))
                  .fontSize(24).margin({right:12})

                Column() {
                  Text(item)
                    .fontSize(16)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .onClick(() => this.onItemClick(item)) // 点击整行也能触发

                // ⭐ 非编辑模式：显示操作按钮
                if (!this.isEditMode && item.indexOf('.') !== -1) {
                  Button('分享')
                    .fontSize(12)
                    .height(28)
                    .backgroundColor('#2196F3')
                    .fontColor(Color.White)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.shareFile(item);
                    })

                  Button('删除')
                    .fontSize(12)
                    .height(28)
                    .backgroundColor('#E53935')
                    .fontColor(Color.White)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.deleteFile(item);
                    })
                }

                if (!this.isEditMode && item.indexOf('.') === -1) {
                  Text('>').fontSize(14).fontColor('#CCC').margin({ left: 8 })
                }
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .border({ width: { bottom: 1 }, color: '#EEEEEE' })
            }
          })
        }
        .layoutWeight(1)
        .width('100%')

        // ⭐ 新增：底部批量操作栏
        if (this.isEditMode) {
          Row() {
            Row() {
              Checkbox()
                .select(this.displayFiles.length > 0 && this.selectedFiles.length === this.displayFiles.length)
                .onChange(() => this.toggleSelectAll())
              Text('全选').fontSize(16).margin({ left: 4 })
            }.layoutWeight(1)

            Text(`已选: ${this.selectedFiles.length}`).fontSize(14).fontColor('#666').margin({ right: 16 })

            Button('分享')
              .fontSize(14)
              .height(32)
              .backgroundColor('#2196F3')
              .fontColor(Color.White)
              .margin({ right: 8 })
              .onClick(() => this.batchShare())

            Button('删除')
              .fontSize(14)
              .height(32)
              .backgroundColor('#E53935')
              .fontColor(Color.White)
              .onClick(() => this.batchDelete())
          }
          .width('100%')
          .height(60)
          .backgroundColor('#F5F5F5')
          .padding({ left: 16, right: 16 })
          .border({ width: { top: 1 }, color: '#DDD' })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      // 2. 图片预览遮罩
      if (this.previewImagePath) {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image('file://' + this.previewImagePath)
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Black)

            Button('✕')
              .fontSize(20)
              .fontColor(Color.White)
              .backgroundColor('#80000000')
              .width(40)
              .height(40)
              .margin({ top: 40, right: 20 })
              .onClick(() => {
                this.previewImagePath = '';
              })

            Button('分享')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#802196F3')
              .height(36)
              .margin({ top: 40, right: 70 })
              .onClick(() => {
                const name = this.previewImagePath.split('/').pop();
                if (name) this.shareFile(name);
              })

            Button('删除')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#CCDD2C00')
              .height(36)
              .margin({ top: 40, right: 140 })
              .onClick(() => {
                const name = this.previewImagePath.split('/').pop();
                if (name) this.deleteFile(name);
              })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .zIndex(999)
        .onClick(() => {
          this.previewImagePath = '';
        })
      }

      // 3. 文本/CSV查看遮罩
      if (this.isViewingText) {
        Column() {
          Row() {
            Text(this.viewingFileName).fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)

            Button('删除')
              .fontSize(14)
              .fontColor('#E53935')
              .backgroundColor(Color.Transparent)
              .margin({ right: 10 })
              .onClick(() => {
                this.deleteFile(this.viewingFileName);
              })

            Button('✕')
              .fontSize(18)
              .backgroundColor(Color.Transparent)
              .fontColor('#333')
              .onClick(() => { this.isViewingText = false; })
          }
          .height(50)
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor('#F5F5F5')
          .border({ width: { bottom: 1 }, color: '#DDD' })

          Scroll() {
            Text(this.textContent)
              .fontSize(14)
              .fontColor('#333')
              .padding(16)
              .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor('#FFF')
          .align(Alignment.TopStart)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#FFF')
        .zIndex(998)
      }
    }
  }
}