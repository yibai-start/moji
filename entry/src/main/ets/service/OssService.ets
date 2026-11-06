import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const PREF_NAME: string = 'oss_prefs';
const KEY_ENABLED: string = 'oss_enabled';
const KEY_ENDPOINT: string = 'oss_endpoint';
const KEY_BUCKET: string = 'oss_bucket';
const KEY_ACCESS_KEY_ID: string = 'oss_access_key_id';
const KEY_ACCESS_KEY_SECRET: string = 'oss_access_key_secret';
const KEY_PATH_PREFIX: string = 'oss_path_prefix';
const KEY_UPLOADED: string = 'oss_uploaded';
const DEFAULT_PREFIX: string = 'moji/images';
const PROBE_NAME: string = '.moji_probe.txt';

export class OssConfig {
  enabled: boolean = false;
  endpoint: string = '';
  bucket: string = '';
  accessKeyId: string = '';
  accessKeySecret: string = '';
  pathPrefix: string = DEFAULT_PREFIX;
}

export class OssUploadResult {
  ok: number = 0;
  failed: number = 0;
  skipped: number = 0;
  message: string = '';
}

export class OssService {
  static config(context: common.UIAbilityContext): OssConfig {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    const cfg: OssConfig = new OssConfig();
    cfg.enabled = pref.getSync(KEY_ENABLED, false) as boolean;
    cfg.endpoint = pref.getSync(KEY_ENDPOINT, '') as string;
    cfg.bucket = pref.getSync(KEY_BUCKET, '') as string;
    cfg.accessKeyId = pref.getSync(KEY_ACCESS_KEY_ID, '') as string;
    cfg.accessKeySecret = pref.getSync(KEY_ACCESS_KEY_SECRET, '') as string;
    cfg.pathPrefix = pref.getSync(KEY_PATH_PREFIX, DEFAULT_PREFIX) as string;
    if (cfg.pathPrefix.trim().length === 0) {
      cfg.pathPrefix = DEFAULT_PREFIX;
    }
    return cfg;
  }

  static saveConfig(context: common.UIAbilityContext, cfg: OssConfig): void {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    pref.putSync(KEY_ENABLED, cfg.enabled);
    pref.putSync(KEY_ENDPOINT, cfg.endpoint.trim());
    pref.putSync(KEY_BUCKET, cfg.bucket.trim());
    pref.putSync(KEY_ACCESS_KEY_ID, cfg.accessKeyId.trim());
    pref.putSync(KEY_ACCESS_KEY_SECRET, cfg.accessKeySecret.trim());
    pref.putSync(KEY_PATH_PREFIX, cfg.pathPrefix.trim().length === 0 ? DEFAULT_PREFIX : cfg.pathPrefix.trim());
    pref.flush();
  }

  static isReady(cfg: OssConfig): boolean {
    return cfg.enabled
      && cfg.endpoint.trim().length > 0
      && cfg.bucket.trim().length > 0
      && cfg.accessKeyId.trim().length > 0
      && cfg.accessKeySecret.trim().length > 0;
  }

  static uploadedNames(context: common.UIAbilityContext): Set<string> {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    const raw: string = pref.getSync(KEY_UPLOADED, '[]') as string;
    try {
      const list: string[] = JSON.parse(raw) as string[];
      return new Set<string>(list);
    } catch (err) {
      return new Set<string>();
    }
  }

  private static markUploaded(context: common.UIAbilityContext, fileName: string): void {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    const names: Set<string> = OssService.uploadedNames(context);
    names.add(fileName);
    pref.putSync(KEY_UPLOADED, JSON.stringify(Array.from(names)));
    pref.flush();
  }

  static async upload(context: common.UIAbilityContext, cfg: OssConfig, fileName: string): Promise<void> {
    await OssService.putObject(context, cfg, fileName);
    OssService.markUploaded(context, fileName);
  }

  private static uploading: boolean = false;

  static async uploadPending(context: common.UIAbilityContext, cfg: OssConfig, fileNames?: string[]): Promise<OssUploadResult> {
    if (OssService.uploading) {
      const result: OssUploadResult = new OssUploadResult();
      result.message = '已有上传任务在进行中';
      return result;
    }
    OssService.uploading = true;
    try {
      let list: string[] = fileNames === undefined ? [] : fileNames;
      if (list === undefined) {
        const dir: string = `${context.filesDir}/images`;
        list = fileIo.accessSync(dir) ? fileIo.listFileSync(dir) : [];
      }
      const uploaded: Set<string> = OssService.uploadedNames(context);
      const result: OssUploadResult = new OssUploadResult();
      let firstError: string = '';
      for (const name of list) {
        if (uploaded.has(name) || !fileIo.accessSync(`${context.filesDir}/images/${name}`)) {
          result.skipped++;
          continue;
        }
        try {
          await OssService.upload(context, cfg, name);
          result.ok++;
        } catch (err) {
          result.failed++;
          if (firstError.length === 0) {
            firstError = OssService.errorMessage(err);
          }
          hilog.error(0x0000, 'MojiOss', 'upload %{public}s failed: %{public}s', name, firstError);
        }
      }
      result.message = firstError;
      return result;
    } finally {
      OssService.uploading = false;
    }
  }

  static syncInBackground(context: common.UIAbilityContext, fileNames: string[]): void {
    const cfg: OssConfig = OssService.config(context);
    if (!OssService.isReady(cfg) || fileNames.length === 0) {
      return;
    }
    OssService.uploadPending(context, cfg, fileNames).catch((err: BusinessError) => {
      hilog.error(0x0000, 'MojiOss', 'background sync failed: %{public}s', JSON.stringify(err));
    });
  }

  static async testConnection(context: common.UIAbilityContext, cfg: OssConfig): Promise<void> {
    const date: string = new Date().toUTCString();
    const objectKey: string = `${OssService.cleanPrefix(cfg.pathPrefix)}/${PROBE_NAME}`;
    await OssService.request(context, cfg, 'PUT', objectKey, 'text/plain',
      new util.TextEncoder().encodeInto('moji oss probe'), date);
    await OssService.request(context, cfg, 'DELETE', objectKey, '',
      new ArrayBuffer(0), date);
  }

  private static async putObject(context: common.UIAbilityContext, cfg: OssConfig, fileName: string): Promise<void> {
    const path: string = `${context.filesDir}/images/${fileName}`;
    const stat: fileIo.Stat = fileIo.statSync(path);
    const body: ArrayBuffer = new ArrayBuffer(stat.size);
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.readSync(file.fd, body);
    } finally {
      fileIo.closeSync(file);
    }
    const date: string = new Date().toUTCString();
    const objectKey: string = `${OssService.cleanPrefix(cfg.pathPrefix)}/${fileName}`;
    await OssService.request(context, cfg, 'PUT', objectKey, OssService.contentTypeOf(fileName), body, date);
  }

  private static async request(context: common.UIAbilityContext, cfg: OssConfig, verb: string,
    objectKey: string, contentType: string, body: ArrayBuffer, date: string): Promise<void> {
    const resource: string = `/${cfg.bucket.trim()}/${objectKey}`;
    const stringToSign: string = `${verb}\n\n${contentType}\n${date}\nx-oss-date:${date}\n${resource}`;
    const signature: string = await OssService.hmacSha1Base64(cfg.accessKeySecret.trim(), stringToSign);
    const url: string = `https://${cfg.bucket.trim()}.${cfg.endpoint.trim()}/${OssService.encodePath(objectKey)}`;
    const headers: Record<string, string> = {
      'Date': date,
      'x-oss-date': date,
      'Authorization': `OSS ${cfg.accessKeyId.trim()}:${signature}`
    };
    if (contentType.length > 0) {
      headers['Content-Type'] = contentType;
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: verb === 'PUT' ? http.RequestMethod.PUT : http.RequestMethod.DELETE,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${OssService.ossErrorMessage(String(resp.result))}`);
      }
    } finally {
      client.destroy();
    }
  }

  private static async hmacSha1Base64(secret: string, text: string): Promise<string> {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyBlob: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(secret) };
    const symKey: cryptoFramework.SymKey = await generator.convertKey(keyBlob);
    const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA1');
    await mac.init(symKey);
    await mac.update({ data: new util.TextEncoder().encodeInto(text) });
    const out: cryptoFramework.DataBlob = await mac.doFinal();
    return new util.Base64Helper().encodeToStringSync(out.data);
  }

  private static cleanPrefix(prefix: string): string {
    let value: string = prefix.trim();
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.length === 0 ? DEFAULT_PREFIX : value;
  }

  private static encodePath(objectKey: string): string {
    const parts: string[] = objectKey.split('/');
    const encoded: string[] = [];
    for (const part of parts) {
      encoded.push(encodeURIComponent(part));
    }
    return encoded.join('/');
  }

  private static contentTypeOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    const ext: string = dot < 0 ? '' : fileName.substring(dot).toLowerCase();
    if (ext === '.jpg' || ext === '.jpeg') {
      return 'image/jpeg';
    }
    if (ext === '.png') {
      return 'image/png';
    }
    if (ext === '.gif') {
      return 'image/gif';
    }
    if (ext === '.webp') {
      return 'image/webp';
    }
    if (ext === '.bmp') {
      return 'image/bmp';
    }
    return 'application/octet-stream';
  }

  private static ossErrorMessage(body: string): string {
    const match: RegExpMatchArray | null = body.match(/<Message>([\s\S]*?)<\/Message>/);
    return match === null ? '' : match[1];
  }

  static errorMessage(err: BusinessError | Error | undefined): string {
    if (err === undefined) {
      return '未知错误';
    }
    const e: BusinessError = err as BusinessError;
    if (typeof e.message === 'string' && e.message.length > 0) {
      return e.message;
    }
    return `错误码 ${e.code}`;
  }
}
