import bcrypt from 'bcrypt';
import { pool } from './pool.js';

async function seed(): Promise<void> {
  const passwordHash = await bcrypt.hash('Admin123!', 12);
  const supervisorHash = await bcrypt.hash('Supervisor123!', 12);
  const workerHash = await bcrypt.hash('Worker123!', 12);

  const { rows: existing } = await pool.query(
    "SELECT id FROM users WHERE email = 'admin@spatialverify.com'"
  );
  if (existing.length > 0) {
    console.log('Seed data already exists, skipping.');
    await pool.end();
    return;
  }

  const { rows: users } = await pool.query(`
    INSERT INTO users (email, password_hash, first_name, last_name, role) VALUES
      ('admin@spatialverify.com', $1, 'System', 'Admin', 'admin'),
      ('supervisor@spatialverify.com', $2, 'Field', 'Supervisor', 'supervisor'),
      ('worker@spatialverify.com', $3, 'Field', 'Worker', 'field_worker')
    RETURNING id, email, role
  `, [passwordHash, supervisorHash, workerHash]);

  const adminId = users[0].id;
  const supervisorId = users[1].id;
  const workerId = users[2].id;

  const { rows: projects } = await pool.query(`
    INSERT INTO projects (name, description, boundary, survey_rules, created_by) VALUES
      ('Downtown Survey', 'Urban infrastructure survey zone',
       ST_SetSRID(ST_GeomFromText('POLYGON((-122.42 37.77, -122.40 37.77, -122.40 37.79, -122.42 37.79, -122.42 37.77))'), 4326),
       '{"min_confidence": 0.6, "require_photo": true, "max_speed_kmh": 10}'::jsonb,
       $1)
    RETURNING id
  `, [adminId]);

  const projectId = projects[0].id;

  await pool.query(`
    INSERT INTO asset_categories (project_id, name, description, detection_labels, icon, color) VALUES
      ($1, 'Utility Pole', 'Electrical/telecom poles', '["pole", "utility_pole"]'::jsonb, 'bolt', '#FFD700'),
      ($1, 'Fire Hydrant', 'Street fire hydrants', '["hydrant", "fire_hydrant"]'::jsonb, 'water_drop', '#FF4444'),
      ($1, 'Manhole Cover', 'Street manhole covers', '["manhole", "manhole_cover"]'::jsonb, 'circle', '#888888'),
      ($1, 'Street Sign', 'Traffic and street signs', '["sign", "street_sign"]'::jsonb, 'signpost', '#4488FF')
  `, [projectId]);

  const { rows: teams } = await pool.query(`
    INSERT INTO teams (project_id, name) VALUES ($1, 'Alpha Team') RETURNING id
  `, [projectId]);

  await pool.query(`
    INSERT INTO team_members (team_id, user_id) VALUES
      ($1, $2),
      ($1, $3)
  `, [teams[0].id, supervisorId, workerId]);

  console.log('Seed data created successfully.');
  console.log('Users:', users.map((u: { email: string; role: string }) => `${u.email} (${u.role})`).join(', '));
  await pool.end();
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
