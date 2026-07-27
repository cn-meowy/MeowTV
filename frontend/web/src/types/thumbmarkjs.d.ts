declare module 'thumbmarkjs' {
  interface componentInterface {
    [key: string]: string | string[] | number | boolean | componentInterface;
  }

  export function getFingerprintData(): Promise<componentInterface>;
  export function getFingerprint(includeData?: false): Promise<string>;
  export function getFingerprint(includeData: true): Promise<{
    hash: string;
    data: componentInterface;
  }>;
  export function getFingerprintPerformance(): Promise<{
    [key: string]: any;
  }>;
  export function getVersion(): string;

  interface optionsInterface {
    exclude?: string[];
    include?: string[];
    webgl_runs?: number;
    canvas_runs?: number;
    permissions_to_check?: PermissionName[];
    retries?: number;
    timeout?: number;
  }
  export function setOption<K extends keyof optionsInterface>(key: K, value: optionsInterface[K]): void;
}
