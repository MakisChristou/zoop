-- Gravity vector from R18 (g), for posture-angle based sleep methods.
ALTER TABLE samples
    ADD COLUMN gravity_x REAL,
    ADD COLUMN gravity_y REAL,
    ADD COLUMN gravity_z REAL;
