"use strict";
const { Client } = require("pg");

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("DATABASE_URL is not set");
  }
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const res = await client.query("SELECT 1 AS one");
    if (res.rows[0].one !== 1) {
      throw new Error(`unexpected result from SELECT 1: ${JSON.stringify(res.rows)}`);
    }
    console.log("SELECT 1 ok:", res.rows[0]);
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
