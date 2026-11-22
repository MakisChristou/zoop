-- Null distinguishes existing installations whose iPhone target has not migrated.
ALTER TABLE profiles ADD COLUMN sleep_goal_minutes INTEGER
    CHECK (sleep_goal_minutes BETWEEN 60 AND 1440 AND sleep_goal_minutes % 15 = 0);
