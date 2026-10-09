/**
 * FuncParser —— y=f(x) 表达式解析与安全求值。
 * 支持一次、二次、反比例、指数、对数、三角等常见初等函数语法；
 * 非法表达式返回 ModelResult 失败并携带错误位置信息。
 */
import { ModelResult, failResult, okResult } from '../model/Constants';

export type FnOfX = (x: number) => number;

interface AstNode {
  kind: string;
  value: number;
  name: string;
  left: AstNode | undefined;
  right: AstNode | undefined;
}

interface ParseExprResult {
  node: AstNode | undefined;
  index: number;
}

const MATH_FUNCS: string[] = ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sqrt', 'abs', 'exp', 'log', 'ln'];

const TOKEN_RE: RegExp = /^([0-9]+(\.[0-9]+)?|[a-zA-Z]+|[+\-*/^(),.])/;

export class FuncParser {
  /** 解析表达式，返回求值闭包 */
  static parseFuncY(expr: string): ModelResult<FnOfX> {
    const trimmed = expr ? expr.trim() : '';
    if (trimmed.length === 0) {
      return failResult('位置 0: 表达式为空');
    }
    // 标准化：允许 y= 前缀与中文等号
    let normalized = trimmed;
    if (normalized.startsWith('y=') || normalized.startsWith('Y=')) {
      normalized = normalized.substring(2);
    }
    // 将 ^ 保留为幂符号
    try {
      const tokens = FuncParser.tokenize(normalized);
      const parser = new FuncParser();
      const pos = parser.parseExpr(tokens, 0);
      if (pos.index < tokens.length) {
        return failResult(`位置 ${pos.index}: 存在无法解析的字符`);
      }
      const root = pos.node;
      if (!root) {
        return failResult('位置 0: 表达式无效');
      }
      const fn: FnOfX = (x: number): number => FuncParser.evalNode(root, x);
      return okResult(fn);
    } catch (err) {
      const msg = err instanceof Error ? err.message : '表达式无效';
      return failResult(msg);
    }
  }

  private static tokenize(expr: string): string[] {
    const tokens: string[] = [];
    let i = 0;
    while (i < expr.length) {
      const ch = expr.charAt(i);
      if (ch === ' ' || ch === '\t' || ch === '（' || ch === '）') {
        i++;
        continue;
      }
      if (ch === '×' || ch === '*' || ch === '·') {
        tokens.push('*');
        i++;
        continue;
      }
      if (ch === '÷' || ch === '/') {
        tokens.push('/');
        i++;
        continue;
      }
      if (ch === '−' || ch === '—' || ch === '–' || ch === '－') {
        tokens.push('-');
        i++;
        continue;
      }
      if (ch === '＋' || ch === '+') {
        tokens.push('+');
        i++;
        continue;
      }
      if (ch === '^' || ch === '²' || ch === '³') {
        if (ch === '²') {
          tokens.push('^');
          tokens.push('2');
        } else if (ch === '³') {
          tokens.push('^');
          tokens.push('3');
        } else {
          tokens.push('^');
        }
        i++;
        continue;
      }
      if (ch === '(' || ch === ')') {
        tokens.push(ch);
        i++;
        continue;
      }
      if (ch === '.' || (ch >= '0' && ch <= '9')) {
        let num = '';
        while (i < expr.length && ((expr.charAt(i) >= '0' && expr.charAt(i) <= '9') || expr.charAt(i) === '.')) {
          num += expr.charAt(i);
          i++;
        }
        tokens.push(num);
        continue;
      }
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        let word = '';
        while (i < expr.length && ((expr.charAt(i) >= 'a' && expr.charAt(i) <= 'z') || (expr.charAt(i) >= 'A' && expr.charAt(i) <= 'Z'))) {
          word += expr.charAt(i);
          i++;
        }
        tokens.push(word);
        continue;
      }
      throw new Error(`位置 ${i}: 无法识别的字符「${ch}」`);
    }
    return tokens;
  }

  private index: number = 0;
  private tokens: string[] = [];

  private parseExpr(tokens: string[], start: number): ParseExprResult {
    this.tokens = tokens;
    this.index = start;
    let leftNode = this.parseTerm();
    while (this.index < tokens.length) {
      const op = tokens[this.index];
      if (op === '+' || op === '-') {
        this.index++;
        const right = this.parseTerm();
        leftNode = this.makeNode(op === '+' ? 'add' : 'sub', leftNode, right);
      } else {
        break;
      }
    }
    return { node: leftNode, index: this.index };
  }

  private parseTerm(): AstNode {
    let left = this.parsePower();
    while (this.index < this.tokens.length) {
      const op = this.tokens[this.index];
      if (op === '*' || op === '/') {
        this.index++;
        const right = this.parsePower();
        left = this.makeNode(op === '*' ? 'mul' : 'div', left, right);
      } else {
        break;
      }
    }
    return left;
  }

  private parsePower(): AstNode {
    const base = this.parseUnary();
    if (this.index < this.tokens.length && this.tokens[this.index] === '^') {
      this.index++;
      const exp = this.parsePower();
      return this.makeNode('pow', base, exp);
    }
    return base;
  }

  private parseUnary(): AstNode {
    if (this.index < this.tokens.length) {
      const op = this.tokens[this.index];
      if (op === '-') {
        this.index++;
        const operand = this.parseUnary();
        return this.makeNode('neg', operand, undefined);
      }
      if (op === '+') {
        this.index++;
        return this.parseUnary();
      }
    }
    return this.parsePrimary();
  }

  private parsePrimary(): AstNode {
    if (this.index >= this.tokens.length) {
      throw new Error(`位置 ${this.index}: 表达式不完整`);
    }
    const token = this.tokens[this.index];
    // 数字
    if (/^[0-9.]+$/.test(token)) {
      this.index++;
      return this.makeNode('num', undefined, undefined, parseFloat(token));
    }
    // 变量 x
    if (token === 'x') {
      this.index++;
      return this.makeNode('x', undefined, undefined, 0);
    }
    // 常数 e / pi
    if (token === 'e') {
      this.index++;
      return this.makeNode('num', undefined, undefined, Math.E);
    }
    if (token === 'pi' || token === 'π') {
      this.index++;
      return this.makeNode('num', undefined, undefined, Math.PI);
    }
    // 函数
    const lower = token.toLowerCase();
    if (MATH_FUNCS.indexOf(lower) >= 0 || lower === 'pi') {
      this.index++;
      if (this.index < this.tokens.length && this.tokens[this.index] === '(') {
        this.index++;
        const inner = this.parseExprInner();
        if (this.index < this.tokens.length && this.tokens[this.index] === ')') {
          this.index++;
        } else {
          throw new Error(`位置 ${this.index}: 缺少右括号`);
        }
        if (lower === 'pi') {
          return this.makeNode('num', undefined, undefined, Math.PI);
        }
        return this.makeNode('func', inner, undefined, 0, lower);
      }
      throw new Error(`位置 ${this.index}: 函数 ${token} 缺少括号`);
    }
    // 括号
    if (token === '(') {
      this.index++;
      const inner = this.parseExprInner();
      if (this.index >= this.tokens.length || this.tokens[this.index] !== ')') {
        throw new Error(`位置 ${this.index}: 缺少右括号`);
      }
      this.index++;
      return inner;
    }
    throw new Error(`位置 ${this.index}: 无法解析的符号「${token}」`);
  }

  private parseExprInner(): AstNode {
    let leftNode = this.parseTerm();
    while (this.index < this.tokens.length) {
      const op = this.tokens[this.index];
      if (op === '+' || op === '-') {
        this.index++;
        const right = this.parseTerm();
        leftNode = this.makeNode(op === '+' ? 'add' : 'sub', leftNode, right);
      } else {
        break;
      }
    }
    return leftNode;
  }

  private makeNode(kind: string, left: AstNode | undefined, right: AstNode | undefined,
    value: number = 0, name: string = ''): AstNode {
    return { kind: kind, value: value, name: name, left: left, right: right };
  }

  /** AST 求值 */
  private static evalNode(node: AstNode | undefined, x: number): number {
    if (!node) {
      return 0;
    }
    switch (node.kind) {
      case 'num':
        return node.value;
      case 'x':
        return x;
      case 'neg':
        return -FuncParser.evalNode(node.left, x);
      case 'add':
        return FuncParser.evalNode(node.left, x) + FuncParser.evalNode(node.right, x);
      case 'sub':
        return FuncParser.evalNode(node.left, x) - FuncParser.evalNode(node.right, x);
      case 'mul':
        return FuncParser.evalNode(node.left, x) * FuncParser.evalNode(node.right, x);
      case 'div': {
        const d = FuncParser.evalNode(node.right, x);
        if (Math.abs(d) < 1e-12) {
          return NaN;
        }
        return FuncParser.evalNode(node.left, x) / d;
      }
      case 'pow': {
        const b = FuncParser.evalNode(node.left, x);
        const e = FuncParser.evalNode(node.right, x);
        return Math.pow(b, e);
      }
      case 'func':
        return FuncParser.evalFunc(node.name, FuncParser.evalNode(node.left, x));
      default:
        return 0;
    }
  }

  private static evalFunc(name: string, v: number): number {
    switch (name) {
      case 'sin':
        return Math.sin(v);
      case 'cos':
        return Math.cos(v);
      case 'tan':
        return Math.tan(v);
      case 'asin':
        return Math.asin(v);
      case 'acos':
        return Math.acos(v);
      case 'atan':
        return Math.atan(v);
      case 'sqrt':
        return v >= 0 ? Math.sqrt(v) : NaN;
      case 'abs':
        return Math.abs(v);
      case 'exp':
        return Math.exp(v);
      case 'log':
        return v > 0 ? Math.log10(v) : NaN;
      case 'ln':
        return v > 0 ? Math.log(v) : NaN;
      default:
        return NaN;
    }
  }
}