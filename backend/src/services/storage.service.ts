import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../config/env.js';

const s3 = new S3Client({
  endpoint: env.s3.endpoint,
  region: env.s3.region,
  credentials: {
    accessKeyId: env.s3.accessKey,
    secretAccessKey: env.s3.secretKey,
  },
  forcePathStyle: env.s3.forcePathStyle,
});

export class StorageService {
  async upload(key: string, body: Buffer, contentType: string): Promise<string> {
    await s3.send(
      new PutObjectCommand({
        Bucket: env.s3.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
      })
    );
    return key;
  }

  async getPresignedUploadUrl(key: string, contentType: string, expiresIn = 3600): Promise<string> {
    const command = new PutObjectCommand({
      Bucket: env.s3.bucket,
      Key: key,
      ContentType: contentType,
    });
    return getSignedUrl(s3, command, { expiresIn });
  }

  async getPresignedDownloadUrl(key: string, expiresIn = 3600): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: env.s3.bucket,
      Key: key,
    });
    return getSignedUrl(s3, command, { expiresIn });
  }

  async delete(key: string): Promise<void> {
    await s3.send(
      new DeleteObjectCommand({
        Bucket: env.s3.bucket,
        Key: key,
      })
    );
  }

  generateKey(prefix: string, filename: string): string {
    const timestamp = Date.now();
    const sanitized = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
    return `${prefix}/${timestamp}-${sanitized}`;
  }
}

export const storageService = new StorageService();
