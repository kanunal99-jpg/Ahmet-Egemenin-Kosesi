INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  TRUE,
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Avatar upload own folder" ON storage.objects;
DROP POLICY IF EXISTS "Avatar read own metadata" ON storage.objects;
DROP POLICY IF EXISTS "Avatar update own object" ON storage.objects;
DROP POLICY IF EXISTS "Avatar delete own object" ON storage.objects;

CREATE POLICY "Avatar upload own folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

CREATE POLICY "Avatar read own metadata"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'avatars'
  AND owner_id = (SELECT auth.uid()::text)
);

CREATE POLICY "Avatar update own object"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND owner_id = (SELECT auth.uid()::text)
)
WITH CHECK (
  bucket_id = 'avatars'
  AND owner_id = (SELECT auth.uid()::text)
  AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

CREATE POLICY "Avatar delete own object"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND owner_id = (SELECT auth.uid()::text)
);