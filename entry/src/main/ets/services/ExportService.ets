/**
 * ExportService —— 导出与导入。
 * JSON 序列化/反序列化经校验才允许导入建图；图片保存到应用沙箱 files 目录。
 */
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ModelResult, failResult, okResult } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

export interface ExportImageResult {
  path: string;
}

export class ExportService {
  static exportMapToJson(map: MindMap): string {
    return map.toJson();
  }

  static importMap(text: string): ModelResult<MindMap> {
    const trimmed = text ? text.trim() : '';
    if (trimmed.length === 0) {
      return failResult('导入内容为空');
    }
    const map = MindMap.fromJson(trimmed);
    if (!map) {
      return failResult('导入文件格式不正确');
    }
    const validation = map.validate();
    if (!validation.ok) {
      return failResult('导入文件格式不正确');
    }
    return okResult(map);
  }

  /** 保存 PixelMap 为 PNG 到沙箱 files 目录，返回文件路径 */
  static async savePixelMap(pixelMap: image.PixelMap, suggestedName: string): Promise<ExportImageResult> {
    const context = AppContextHolder.get();
    const safeName = suggestedName.replace(/[^\w\u4e00-\u9fa5-]/g, '_');
    const fileName = `zhitu_${safeName}_${Date.now()}.png`;
    const filePath = `${context.filesDir}/${fileName}`;
    try {
      const packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/png', quality: 100 };
      const buffer = await packer.packing(pixelMap, option);
      packer.release();
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file.fd);
      Logger.info('ExportService', `image saved: ${filePath}`);
      return { path: filePath };
    } catch (err) {
      Logger.error('ExportService', `savePixelMap failed: ${JSON.stringify(err)}`);
      return { path: '' };
    }
  }

  /** 保存导图 JSON 文本到沙箱 files 目录，返回文件路径 */
  static async saveJsonToFiles(json: string, suggestedName: string): Promise<ExportImageResult> {
    const context = AppContextHolder.get();
    const safeName = suggestedName.replace(/[^\w\u4e00-\u9fa5-]/g, '_');
    const fileName = `zhitu_${safeName}_${Date.now()}.json`;
    const filePath = `${context.filesDir}/${fileName}`;
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file.fd);
      return { path: filePath };
    } catch (err) {
      Logger.error('ExportService', `saveJsonToFiles failed: ${JSON.stringify(err)}`);
      return { path: '' };
    }
  }

  static async readTextFromFile(filePath: string): Promise<string> {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(filePath);
      const size = stat.size;
      let content = '';
      if (size > 0) {
        const buf = new ArrayBuffer(size);
        fileIo.readSync(file.fd, buf);
        const textDecoder = util.TextDecoder.create('utf-8');
        content = textDecoder.decodeWithStream(new Uint8Array(buf));
      }
      fileIo.closeSync(file.fd);
      return content;
    } catch (err) {
      Logger.error('ExportService', `readTextFromFile failed: ${JSON.stringify(err)}`);
      return '';
    }
  }
}