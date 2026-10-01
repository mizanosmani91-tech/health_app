import crypto from 'node:crypto';
import { NextFunction, Request, Response } from 'express';
import { z, ZodTypeAny } from 'zod';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** Validates with zod; any failure becomes a 400 with a short message. */
export function parse<T extends ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data ?? {});
  if (!r.success) {
    const i = r.error.issues[0];
    throw new HttpError(400, `${i.path.join('.') || 'body'}: ${i.message}`);
  }
  return r.data;
}

export const text = (max: number) => z.string().trim().min(1).max(max);
export const optText = (max: number) =>
  z.preprocess((v) => (v === '' ? null : v), z.string().trim().max(max).nullable().optional());
export const money = z.coerce.number().finite().min(0).max(1e10);
export const optMoney = z.preprocess((v) => (v === '' || v == null ? null : v), z.coerce.number().finite().min(0).max(1e10).nullable().optional());
export const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'must be YYYY-MM-DD');
export const hhmm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'must be HH:MM');
export const today = () => new Date().toISOString().slice(0, 10);

/** Decimal | null -> number | null */
export const n = (v: { toString(): string } | null | undefined) => (v == null ? null : Number(v.toString()));

export function simpleLimit(max: number) {
  const hits = new Map<string, number>();
  setInterval(() => hits.clear(), 60_000).unref();
  return (req: Request, _res: Response, next: NextFunction) => {
    const k = req.ip ?? 'x';
    const c = (hits.get(k) ?? 0) + 1;
    hits.set(k, c);
    next(c > max ? new HttpError(429, 'too many requests') : undefined);
  };
}

export const safeEqual = (a: string, b: string) => {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};
