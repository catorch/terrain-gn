import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { config } from './config.js';

const HOUR_MS = 3_600_000;

@Injectable()
export class StorageService {
  private readonly s3 = new S3Client({
    region: config.S3_REGION,
    endpoint: config.S3_ENDPOINT,
    forcePathStyle: config.S3_FORCE_PATH_STYLE,
    credentials: config.S3_ACCESS_KEY_ID && config.S3_SECRET_ACCESS_KEY ? { accessKeyId: config.S3_ACCESS_KEY_ID, secretAccessKey: config.S3_SECRET_ACCESS_KEY } : undefined,
  });

  /** The URL only accepts this exact content type and byte length, so a client cannot swap in a larger file. */
  presignPut(key: string, contentType: string, sizeBytes: number) {
    return getSignedUrl(this.s3, new PutObjectCommand({ Bucket: config.S3_BUCKET, Key: key, ContentType: contentType, ContentLength: sizeBytes }), {
      expiresIn: 600,
      signableHeaders: new Set(['content-type', 'content-length']),
    });
  }

  /**
   * Signed at the start of the hour, so every request in that hour gets the same URL and the
   * app's image cache keeps working instead of re-downloading photos on a slow connection.
   */
  presignGet(key: string) {
    const signingDate = new Date(Math.floor(Date.now() / HOUR_MS) * HOUR_MS);
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: config.S3_BUCKET, Key: key }), { expiresIn: 7200, signingDate });
  }

  async head(key: string) {
    try {
      const object = await this.s3.send(new HeadObjectCommand({ Bucket: config.S3_BUCKET, Key: key }));
      return { sizeBytes: object.ContentLength, contentType: object.ContentType };
    } catch (error) {
      if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return null;
      throw error;
    }
  }
}
