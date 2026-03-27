import * as fs from 'fs';
import * as path from 'path';

export interface SourceLocation {
  file: string;
  line: number;
}

export class SourceLinker {
  private configPath: string | null;

  constructor(manifestPath: string) {
    this.configPath = this.findConfigFile(manifestPath);
  }

  async findDefinition(entryName: string): Promise<SourceLocation | null> {
    if (!this.configPath || !fs.existsSync(this.configPath)) return null;

    const content = fs.readFileSync(this.configPath, 'utf-8');
    const lines = content.split('\n');

    // Match page('name'), widget('name'), pages('name'), widgets('name')
    const patterns = [
      new RegExp(`(?:page|widget|pages|widgets)\\s*\\(\\s*['"]${escapeRegex(entryName)}['"]`),
    ];

    for (let i = 0; i < lines.length; i++) {
      for (const pattern of patterns) {
        if (pattern.test(lines[i])) {
          return { file: this.configPath, line: i };
        }
      }
    }

    return null;
  }

  private findConfigFile(manifestPath: string): string | null {
    // Look for print_widget.yaml to find config_file setting
    let dir = path.dirname(manifestPath);
    while (dir !== path.dirname(dir)) {
      const yamlPath = path.join(dir, 'print_widget.yaml');
      if (fs.existsSync(yamlPath)) {
        const yaml = fs.readFileSync(yamlPath, 'utf-8');
        const match = yaml.match(/config_file:\s*(.+)/);
        if (match) {
          const configFile = match[1].trim().replace(/['"]/g, '');
          const fullPath = path.join(dir, configFile);
          if (fs.existsSync(fullPath)) return fullPath;
        }
      }

      // Fallback: common patterns
      for (const candidate of [
        'test/prints/print_config.dart',
        'test/print_config.dart',
        'print_widget/config.dart',
      ]) {
        const fullPath = path.join(dir, candidate);
        if (fs.existsSync(fullPath)) return fullPath;
      }

      if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) break;
      dir = path.dirname(dir);
    }

    return null;
  }
}

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
