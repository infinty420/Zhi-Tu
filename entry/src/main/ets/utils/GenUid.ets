/**
 * 全局唯一标识生成工具。
 * 生成业务无关的稳定标识，如 m_<ts>_<rand>/n_<ts>_<rand>。
 */
export class GenUid {
  private static seq: number = 0;

  static next(prefix: string): string {
    GenUid.seq = (GenUid.seq + 1) % 10000;
    const rand: string = Math.floor(Math.random() * 100000).toString();
    const stamp: string = Date.now().toString();
    return `${prefix}_${stamp}_${rand}_${GenUid.seq}`;
  }

  static nextMapId(): string {
    return GenUid.next('m');
  }

  static nextNodeId(): string {
    return GenUid.next('n');
  }

  static nextWrongId(): string {
    return GenUid.next('w');
  }

  static nextEventId(): string {
    return GenUid.next('e');
  }
}