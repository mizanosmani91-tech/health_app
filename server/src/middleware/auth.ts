import { NextFunction, Request, Response } from 'express';
import { jwtVerify } from 'jose';
import { Role, User } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError } from '../http';

declare module 'express-serve-static-core' {
  interface Request {
    user?: User;
  }
}

export function makeAuth(db: Db, key: Uint8Array) {
  const authed = async (req: Request, _res: Response, next: NextFunction) => {
    const h = req.get('authorization') ?? '';
    if (!h.startsWith('Bearer ')) throw new HttpError(401, 'sign in required');
    let sub: string | undefined;
    try {
      sub = (await jwtVerify(h.slice(7), key, { algorithms: ['HS256'] })).payload.sub;
    } catch {
      throw new HttpError(401, 'session expired');
    }
    // The role is always read from the database, never trusted from the token.
    const user = sub ? await db.user.findUnique({ where: { id: sub } }) : null;
    if (!user) throw new HttpError(401, 'unknown user');
    req.user = user;
    next();
  };
  const role = (r: Role) => (req: Request, _res: Response, next: NextFunction) =>
    next(req.user?.role === r ? undefined : new HttpError(403, `${r} account required`));
  return { authed, role };
}
