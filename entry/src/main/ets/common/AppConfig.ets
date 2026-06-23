export class AppConfig {
  /**
   * 全局服务器地址配置 (支持 IP 或 域名)
   * 测试域名时直接在此修改，例如：'test.yourdomain.com'
   */
  //public static readonly SERVER_HOST: string = '43.143.233.195';
  public static readonly SERVER_HOST: string = '43.138.24.214';
  /**
   * 报警分析专用的端口号 (原代码中为 10000)
   */
  public static readonly ALARM_SERVER_PORT: number = 10000;
  
  // 如果有其他通用端口也可以写在这里，例如：
  // public static readonly DEFAULT_PORT: number = 8080; 
}