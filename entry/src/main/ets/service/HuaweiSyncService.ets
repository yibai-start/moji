import { common } from '@kit.AbilityKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { util, buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cloudCommon, cloudStorage } from '@kit.CloudFoundationKit';
import { authentication } from '@kit.AccountKit';
import { http } from '@kit.NetworkKit';
import { BackupService } from './BackupService';
import { ImageService } from './ImageService';

const PREF_NAME: string = 'hw_sync_prefs';
const KEY_ENABLED: string = 'hw_enabled';
const KEY_UPLOADED: string = 'hw_uploaded';
const KEY_AUTH_TOKEN: string = 'hw_auth_token';
const KEY_REFRESH_TOKEN: string = 'hw_refresh_token';
const KEY_USER_OPENID: string = 'hw_user_openid';
const KEY_USER_NAME: string = 'hw_user_name';
const CACHE_TMP_DIR: string = 'hw_sync';
const BACKUP_NAME: string = 'mojian-backup.json';
const TAG: string = 'MojiHwSync';

export class HuaweiSyncResult {
  ok: number = 0;
  failed: number = 0;
  skipped: number = 0;
  message: string = '';
}

export class HwLoginUser {
  openId: string = '';
  displayName: string = '';
}

class HwAuthProvider implements cloudCommon.AuthProvider {
  private accessToken: string = '';
  private refreshToken: string = '';
  private clientId: string = '';
  private clientSecret: string = '';

  update(token: string, rToken: string, cId: string, cSecret: string): void {
    this.accessToken = token;
    this.refreshToken = rToken;
    this.clientId = cId;
    this.clientSecret = cSecret;
  }

  clear(): void {
    this.accessToken = '';
    this.refreshToken = '';
  }

  async getAccessToken(isForceRefresh: boolean): Promise<string> {
    if (isForceRefresh || this.accessToken.length === 0) {
      if (this.refreshToken.length === 0) {
        throw new Error('未登录华为账号，无法获取用户凭据');
      }
      await this.refreshAccessToken();
    }
    return this.accessToken;
  }

  private async refreshAccessToken(): Promise<void> {
    const url: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/token';
    const body: string = `grant_type=refresh_token&client_id=${this.clientId}` +
      `&client_secret=${encodeURIComponent(this.clientSecret)}` +
      `&refresh_token=${encodeURIComponent(this.refreshToken)}`;
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body,
      });
      if (resp.responseCode === 200) {
        const result: Record<string, string> = JSON.parse(resp.result as string) as Record<string, string>;
        this.accessToken = result['access_token'] ?? '';
        const newRefresh: string | undefined = result['refresh_token'];
        if (newRefresh !== undefined && newRefresh.length > 0) {
          this.refreshToken = newRefresh;
        }
      } else {
        throw new Error(`刷新令牌失败: ${resp.responseCode}`);
      }
    } finally {
      httpRequest.destroy();
    }
  }
}

export class HuaweiSyncService {
  static initialized: boolean = false;
  static cloudReady: boolean = false;
  static syncing: boolean = false;
  static loginUser: HwLoginUser | null = null;
  static authProvider: HwAuthProvider = new HwAuthProvider();
  static agcClientId: string = '';
  static agcClientSecret: string = '';

  static init(context: common.UIAbilityContext): boolean {
    if (HuaweiSyncService.initialized) {
      return true;
    }
    try {
      const data: Uint8Array = context.resourceManager.getRawFileContentSync('agconnect-services.json');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const jsonText: string = decoder.decodeToString(data);
      const config: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
      const client: Record<string, string> = config['client'] as Record<string, string>;
      if (client === null || client['client_id'] === undefined || client['client_id'].length === 0) {
        hilog.warn(0x0000, TAG, 'agconnect-services.json missing client_id, treat as unconfigured');
        return false;
      }
      HuaweiSyncService.agcClientId = client['client_id'];
      HuaweiSyncService.agcClientSecret = client['client_secret'] ?? '';
      HuaweiSyncService.initialized = true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(0x0000, TAG, 'init skipped: %{public}d %{public}s', e.code, e.message);
    }
    return HuaweiSyncService.initialized;
  }

  static async getAnonymousPhone(context: common.UIAbilityContext): Promise<string> {
    if (!HuaweiSyncService.initialized) {
      return '';
    }
    try {
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const authRequest: authentication.AuthorizationWithHuaweiIDRequest =
        provider.createAuthorizationWithHuaweiIDRequest();
      authRequest.scopes = ['quickLoginAnonymousPhone'];
      authRequest.state = util.generateRandomUUID();
      authRequest.forceAuthorization = false;
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      const response: authentication.AuthorizationWithHuaweiIDResponse =
        await controller.executeRequest(authRequest) as authentication.AuthorizationWithHuaweiIDResponse;
      const extraInfo: Record<string, string> = response.data?.extraInfo as Record<string, string>;
      return extraInfo?.['quickLoginAnonymousPhone'] ?? '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(0x0000, TAG, 'getAnonymousPhone failed: %{public}d %{public}s', e.code, e.message);
      return '';
    }
  }

  static async processLogin(authCode: string, context: common.UIAbilityContext): Promise<HwLoginUser> {
    if (!HuaweiSyncService.initialized) {
      throw new Error('缺少 agconnect-services.json，请先在 AGC 完成配置');
    }
    const tokenResult: Record<string, string> = await HuaweiSyncService.exchangeAuthCode(authCode);
    const accessToken: string = tokenResult['access_token'] ?? '';
    const rToken: string = tokenResult['refresh_token'] ?? '';
    HuaweiSyncService.authProvider.update(
      accessToken, rToken,
      HuaweiSyncService.agcClientId, HuaweiSyncService.agcClientSecret
    );
    const idToken: string = tokenResult['id_token'] ?? '';
    const user: HwLoginUser = HuaweiSyncService.parseIdToken(idToken);
    HuaweiSyncService.loginUser = user;
    const pref: preferences.Preferences =
      preferences.getPreferencesSync(context, { name: PREF_NAME });
    pref.putSync(KEY_AUTH_TOKEN, accessToken);
    pref.putSync(KEY_REFRESH_TOKEN, rToken);
    pref.putSync(KEY_USER_OPENID, user.openId);
    pref.putSync(KEY_USER_NAME, user.displayName);
    pref.flush();
    HuaweiSyncService.ensureCloud();
    return user;
  }

  private static exchangeAuthCode(authCode: string): Promise<Record<string, string>> {
    const url: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/token';
    const body: string = `grant_type=authorization_code&client_id=${HuaweiSyncService.agcClientId}` +
      `&client_secret=${encodeURIComponent(HuaweiSyncService.agcClientSecret)}` +
      `&code=${encodeURIComponent(authCode)}`;
    const httpRequest: http.HttpRequest = http.createHttp();
    return new Promise<Record<string, string>>((resolve, reject) => {
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body,
      }).then((resp: http.HttpResponse) => {
        if (resp.responseCode === 200) {
          const result: Record<string, string> = JSON.parse(resp.result as string) as Record<string, string>;
          resolve(result);
        } else {
          reject(new Error(`令牌交换失败: ${resp.responseCode}`));
        }
      }).catch((err: BusinessError) => {
        reject(err);
      }).finally(() => {
        httpRequest.destroy();
      });
    });
  }

  private static parseIdToken(idToken: string): HwLoginUser {
    const user: HwLoginUser = new HwLoginUser();
    if (idToken.length === 0) {
      return user;
    }
    try {
      const parts: string[] = idToken.split('.');
      if (parts.length >= 2) {
        let payload: string = parts[1];
        while (payload.length % 4 !== 0) {
          payload += '=';
        }
        const b64: util.Base64Helper = new util.Base64Helper();
        const jsonBytes: Uint8Array = b64.decodeSync(payload);
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        const jsonText: string = decoder.decodeToString(jsonBytes);
        const claims: Record<string, string> = JSON.parse(jsonText) as Record<string, string>;
        user.openId = claims['sub'] ?? '';
        user.displayName = claims['name'] ?? '';
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'parseIdToken failed');
    }
    return user;
  }

  static async restoreLogin(context: common.UIAbilityContext): Promise<boolean> {
    if (!HuaweiSyncService.initialized) {
      return false;
    }
    const pref: preferences.Preferences =
      preferences.getPreferencesSync(context, { name: PREF_NAME });
    const accessToken: string = pref.getSync(KEY_AUTH_TOKEN, '') as string;
    const rToken: string = pref.getSync(KEY_REFRESH_TOKEN, '') as string;
    if (accessToken.length === 0 && rToken.length === 0) {
      return false;
    }
    const user: HwLoginUser = new HwLoginUser();
    user.openId = pref.getSync(KEY_USER_OPENID, '') as string;
    user.displayName = pref.getSync(KEY_USER_NAME, '') as string;
    HuaweiSyncService.loginUser = user;
    HuaweiSyncService.authProvider.update(
      accessToken, rToken,
      HuaweiSyncService.agcClientId, HuaweiSyncService.agcClientSecret
    );
    HuaweiSyncService.ensureCloud();
    return true;
  }

  static async signOut(context: common.UIAbilityContext): Promise<void> {
    HuaweiSyncService.loginUser = null;
    HuaweiSyncService.authProvider.clear();
    HuaweiSyncService.cloudReady = false;
    const pref: preferences.Preferences =
      preferences.getPreferencesSync(context, { name: PREF_NAME });
    pref.deleteSync(KEY_AUTH_TOKEN);
    pref.deleteSync(KEY_REFRESH_TOKEN);
    pref.deleteSync(KEY_USER_OPENID);
    pref.deleteSync(KEY_USER_NAME);
    pref.flush();
  }

  static isEnabled(context: common.UIAbilityContext): boolean {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    return pref.getSync(KEY_ENABLED, false) as boolean;
  }

  static setEnabled(context: common.UIAbilityContext, enabled: boolean): void {
    const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
    pref.putSync(KEY_ENABLED, enabled);
    pref.flush();
  }

  static ensureCloud(): void {
    if (!HuaweiSyncService.cloudReady) {
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: HuaweiSyncService.authProvider
      });
      HuaweiSyncService.cloudReady = true;
    }
  }

  private static uploadedNames(context: common.UIAbilityContext): Set<string> {
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
    const names: Set<string> = HuaweiSyncService.uploadedNames(context);
    names.add(fileName);
    pref.putSync(KEY_UPLOADED, JSON.stringify(Array.from(names)));
    pref.flush();
  }

  private static waitTask(task: request.agent.Task): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      task.on('completed', () => {
        task.off('failed');
        resolve();
      });
      task.on('failed', () => {
        task.off('completed');
        reject(new Error('云端传输失败'));
      });
    });
  }

  private static cacheCopy(context: common.UIAbilityContext, srcPath: string, relName: string): void {
    const dir: string = `${context.cacheDir}/${CACHE_TMP_DIR}`;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    fileIo.copyFileSync(srcPath, `${dir}/${relName}`);
  }

  private static cacheRemove(context: common.UIAbilityContext, relName: string): void {
    try {
      fileIo.unlinkSync(`${context.cacheDir}/${CACHE_TMP_DIR}/${relName}`);
    } catch (err) {
    }
  }

  private static async uploadOne(context: common.UIAbilityContext, cloudPath: string,
    localRelPath: string): Promise<void> {
    const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
    await bucket.deleteFile(cloudPath).catch(() => undefined);
    const task: request.agent.Task = await bucket.uploadFile(context, {
      cloudPath: cloudPath,
      localPath: localRelPath
    });
    await HuaweiSyncService.waitTask(task);
  }

  static async uploadPending(context: common.UIAbilityContext, fileNames?: string[]): Promise<HuaweiSyncResult> {
    const result: HuaweiSyncResult = new HuaweiSyncResult();
    if (HuaweiSyncService.syncing) {
      result.message = '已有同步任务在进行中';
      return result;
    }
    HuaweiSyncService.syncing = true;
    try {
      if (HuaweiSyncService.loginUser === null) {
        result.message = '尚未登录华为账号';
        return result;
      }
      HuaweiSyncService.ensureCloud();
      const uid: string = HuaweiSyncService.loginUser.openId;
      let list: string[] = fileNames === undefined ? [] : fileNames;
      if (fileNames === undefined) {
        const dir: string = `${context.filesDir}/images`;
        list = fileIo.accessSync(dir) ? fileIo.listFileSync(dir) : [];
      }
      const uploaded: Set<string> = HuaweiSyncService.uploadedNames(context);
      let firstError: string = '';
      for (const name of list) {
        const localPath: string = `${context.filesDir}/images/${name}`;
        if (uploaded.has(name) || !fileIo.accessSync(localPath)) {
          result.skipped++;
          continue;
        }
        try {
          HuaweiSyncService.cacheCopy(context, localPath, name);
          await HuaweiSyncService.uploadOne(context, `moji/${uid}/images/${name}`, `${CACHE_TMP_DIR}/${name}`);
          HuaweiSyncService.markUploaded(context, name);
          HuaweiSyncService.cacheRemove(context, name);
          result.ok++;
        } catch (err) {
          result.failed++;
          const msg: string = HuaweiSyncService.errorMessage(err);
          if (firstError.length === 0) {
            firstError = msg;
          }
          hilog.error(0x0000, TAG, 'upload %{public}s failed: %{public}s', name, msg);
        }
      }
      try {
        const text: string = await new BackupService().exportText();
        const tmpRel: string = `${CACHE_TMP_DIR}/${BACKUP_NAME}`;
        const tmpPath: string = `${context.cacheDir}/${tmpRel}`;
        const file: fileIo.File = fileIo.openSync(tmpPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, text);
        } finally {
          fileIo.closeSync(file);
        }
        await HuaweiSyncService.uploadOne(context, `moji/${uid}/${BACKUP_NAME}`, tmpRel);
        HuaweiSyncService.cacheRemove(context, BACKUP_NAME);
        result.ok++;
      } catch (err) {
        result.failed++;
        const msg: string = HuaweiSyncService.errorMessage(err);
        if (firstError.length === 0) {
          firstError = msg;
        }
        hilog.error(0x0000, TAG, 'backup upload failed: %{public}s', msg);
      }
      result.message = firstError;
      return result;
    } finally {
      HuaweiSyncService.syncing = false;
    }
  }

  static syncInBackground(context: common.UIAbilityContext, fileNames: string[]): void {
    if (!HuaweiSyncService.initialized || fileNames.length === 0) {
      return;
    }
    if (!HuaweiSyncService.isEnabled(context)) {
      return;
    }
    HuaweiSyncService.uploadPending(context, fileNames).catch((err: BusinessError) => {
      hilog.error(0x0000, TAG, 'background sync failed: %{public}s', JSON.stringify(err));
    });
  }

  static async restore(context: common.UIAbilityContext): Promise<HuaweiSyncResult> {
    const result: HuaweiSyncResult = new HuaweiSyncResult();
    if (HuaweiSyncService.loginUser === null) {
      result.message = '尚未登录华为账号';
      return result;
    }
    HuaweiSyncService.ensureCloud();
    const uid: string = HuaweiSyncService.loginUser.openId;
    const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
    const tmpDir: string = `${context.cacheDir}/${CACHE_TMP_DIR}`;
    if (!fileIo.accessSync(tmpDir)) {
      fileIo.mkdirSync(tmpDir, true);
    }
    const localBackupPath: string = `${tmpDir}/${BACKUP_NAME}`;
    const task: request.agent.Task = await bucket.downloadFile(context, {
      cloudPath: `moji/${uid}/${BACKUP_NAME}`,
      localPath: `${CACHE_TMP_DIR}/${BACKUP_NAME}`,
      overwrite: true
    });
    await HuaweiSyncService.waitTask(task);
    const file: fileIo.File = fileIo.openSync(localBackupPath, fileIo.OpenMode.READ_ONLY);
    let text: string = '';
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      text = decoder.decodeToString(new Uint8Array(buffer));
    } finally {
      fileIo.closeSync(file);
    }
    result.ok = await new BackupService().importText(text);

    const list: cloudStorage.ListResults = await bucket.list(`moji/${uid}/images/`, { maxResults: 1000 });
    for (const cloudFile of list.files) {
      const name: string = cloudFile.split('/').pop() ?? '';
      if (name.length === 0) {
        continue;
      }
      if (ImageService.exists(context, name)) {
        result.skipped++;
        continue;
      }
      try {
        const dl: request.agent.Task = await bucket.downloadFile(context, {
          cloudPath: cloudFile,
          localPath: `${CACHE_TMP_DIR}/restore_${name}`,
          overwrite: true
        });
        await HuaweiSyncService.waitTask(dl);
        fileIo.copyFileSync(`${tmpDir}/restore_${name}`, ImageService.pathOf(context, name));
        HuaweiSyncService.cacheRemove(context, `restore_${name}`);
        result.ok++;
      } catch (err) {
        result.failed++;
        const msg: string = HuaweiSyncService.errorMessage(err);
        if (result.message.length === 0) {
          result.message = msg;
        }
        hilog.error(0x0000, TAG, 'restore %{public}s failed: %{public}s', name, msg);
      }
    }
    return result;
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
