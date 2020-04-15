# frozen_string_literal: true

class AddImageUploadIdToPostsAndTopics < ActiveRecord::Migration[6.0]
  def change
    add_reference :posts, :image_upload, foreign_key: { to_table: :uploads, on_delete: :nullify }
    add_reference :topics, :image_upload, foreign_key: { to_table: :uploads, on_delete: :nullify }

    # No need to run this on rollback
    reversible { |c| c.up do
      # Defining regex here to avoid needing to double-escape the \ characters
      regex = '\/(original|optimized)\/\dX[\/\.\w]*\/([a-zA-Z0-9]+)[\.\w]*'

      execute <<~SQL
        CREATE TEMPORARY TABLE tmp_post_image_uploads(
          post_id int primary key,
          upload_id int
        )
      SQL

      # Look for an SHA1 in the existing image_url, and match to the uploads table
      execute <<~SQL
        INSERT INTO tmp_post_image_uploads(post_id, upload_id)
        SELECT
          posts.id as post_id,
          uploads.id as upload_id
        FROM posts
        LEFT JOIN LATERAL regexp_matches(posts.image_url, '#{regex}') matched_sha1 ON TRUE
        LEFT JOIN uploads on uploads.sha1 = matched_sha1[2]
        WHERE posts.image_url IS NOT NULL
        AND uploads.id IS NOT NULL
      SQL

      execute <<~SQL
        UPDATE posts SET image_upload_id = tmp_post_image_uploads.upload_id
        FROM tmp_post_image_uploads
        WHERE tmp_post_image_uploads.post_id = posts.id
      SQL

      # Update the topic image based on the first post image
      execute <<~SQL
        UPDATE topics SET image_upload_id = posts.image_upload_id
        FROM posts
        WHERE posts.topic_id = topics.id
        AND posts.post_number = 1
        AND posts.image_upload_id IS NOT NULL
      SQL

      # For posts we couldn't figure out, mark them for background rebake
      execute <<~SQL
        UPDATE posts SET baked_version = NULL
        WHERE posts.image_url IS NOT NULL
        AND posts.image_upload_id IS NULL
      SQL
    end }

    add_column :theme_modifier_sets, :topic_thumbnail_sizes, :string, array: true
  end
end