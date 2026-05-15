import * as joi from 'joi';

interface EnvVars {
  PORT: number;
  DATABASE_URL: string;
  FIREBASE_SERVICE_ACCOUNT_JSON?: string;
  FIREBASE_PROJECT_ID?: string;
}

const envSchema = joi
  .object({
    PORT: joi.number().required(),
    DATABASE_URL: joi.string().required(),
    FIREBASE_SERVICE_ACCOUNT_JSON: joi.string().optional(),
    FIREBASE_PROJECT_ID: joi.string().optional(),
  })
  .unknown(true);

const { error, value } = envSchema.validate(process.env);

if (error) {
  throw new Error(`ENV config validation error: ${error.message}`);
}

const envVars: EnvVars = value;

export const envs = {
  port: envVars.PORT,
  databaseUrl: envVars.DATABASE_URL,
  firebaseServiceAccountJson: envVars.FIREBASE_SERVICE_ACCOUNT_JSON,
  firebaseProjectId: envVars.FIREBASE_PROJECT_ID,
};
