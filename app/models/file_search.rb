# Searching a user's own drive.
#
# Every query is built from the owner's associations and from a fixed set of
# categories, so no user supplied value ever reaches SQL as anything other than
# a bound parameter.
class FileSearch
  CATEGORIES = StoredFile::CATEGORIES.keys.freeze
  RESULT_LIMIT = 200

  attr_reader :user, :term, :folder, :category

  def initialize(user:, term: nil, folder: nil, category: nil)
    @user = user
    @term = term.to_s.strip.presence
    @folder = folder
    @category = category.to_s.presence_in(CATEGORIES)
  end

  def files
    scope = user.stored_files.kept.includes(:folder)
    scope = scope.named_like(term) if term
    scope = scope.of_category(category) if category
    scope = scope.where(folder_id: folder_scope_ids) if folder

    scope.ordered.limit(RESULT_LIMIT)
  end

  # Folders are matched on their name only; a type filter does not apply.
  def folders
    return Folder.none if category

    scope = user.folders.kept
    scope = scope.where("folders.name ILIKE ?", "%#{Folder.sanitize_sql_like(term)}%") if term
    scope = scope.where(id: folder_scope_ids - [ folder.id ]) if folder

    scope.ordered.limit(RESULT_LIMIT)
  end

  def filtered?
    term.present? || folder.present? || category.present?
  end

  def total_count
    files.size + folders.size
  end

  private
    # The searched folder and everything underneath it.
    def folder_scope_ids
      @folder_scope_ids ||= folder.self_and_descendant_ids
    end
end
