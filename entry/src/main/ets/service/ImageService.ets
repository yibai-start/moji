import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';

const IMAGE_DIR: string = 'images';
const KNOWN_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'];

export class ImageService {
  static directory(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${IMAGE_DIR}`;
  }

  static ensureDirectory(context: common.UIAbilityContext): void {
    const dir: string = ImageService.directory(context);
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
  }

  static async pick(context: common.UIAbilityContext): Promise<string[]> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 9;
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    if (result.photoUris.length === 0) {
      return [];
    }
    ImageService.ensureDirectory(context);
    const stored: string[] = [];
    for (let i = 0; i < result.photoUris.length; i++) {
      const uri: string = result.photoUris[i];
      const name: string = `img_${Date.now()}_${i}_${Math.floor(Math.random() * 1000)}${ImageService.extensionOf(uri)}`;
      const source: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.copyFileSync(source.fd, `${ImageService.directory(context)}/${name}`);
      } finally {
        fileIo.closeSync(source);
      }
      stored.push(name);
    }
    return stored;
  }

  static displayUri(context: common.UIAbilityContext, fileName: string): string {
    return fileUri.getUriFromPath(`${ImageService.directory(context)}/${fileName}`);
  }

  static pathOf(context: common.UIAbilityContext, fileName: string): string {
    return `${ImageService.directory(context)}/${fileName}`;
  }

  static exists(context: common.UIAbilityContext, fileName: string): boolean {
    return fileIo.accessSync(ImageService.pathOf(context, fileName));
  }

  static remove(context: common.UIAbilityContext, fileName: string): void {
    const path: string = ImageService.pathOf(context, fileName);
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
  }

  static removeAll(context: common.UIAbilityContext, fileNames: string[]): void {
    for (const name of fileNames) {
      ImageService.remove(context, name);
    }
  }

  static prune(context: common.UIAbilityContext, keep: string[]): void {
    const dir: string = ImageService.directory(context);
    if (!fileIo.accessSync(dir)) {
      return;
    }
    const entries: string[] = fileIo.listFileSync(dir);
    for (const entry of entries) {
      if (keep.indexOf(entry) < 0) {
        ImageService.remove(context, entry);
      }
    }
  }

  private static extensionOf(uri: string): string {
    const queryIndex: number = uri.indexOf('?');
    const clean: string = queryIndex < 0 ? uri : uri.substring(0, queryIndex);
    const dot: number = clean.lastIndexOf('.');
    if (dot < 0) {
      return '.jpg';
    }
    const ext: string = clean.substring(dot).toLowerCase();
    for (const item of KNOWN_EXTENSIONS) {
      if (ext === item) {
        return ext;
      }
    }
    return '.jpg';
  }
}
