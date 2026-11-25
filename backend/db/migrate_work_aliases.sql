CREATE TABLE IF NOT EXISTS work_aliases (
 normalized_alias VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin PRIMARY KEY,
 alias_name VARCHAR(191) NOT NULL,
 work_id BIGINT UNSIGNED NOT NULL,
 KEY idx_work_alias_owner(work_id),
 FOREIGN KEY(work_id) REFERENCES works(id) ON DELETE CASCADE
);
