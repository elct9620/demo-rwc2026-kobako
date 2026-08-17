require "test_helper"

# The three sources answer in three shapes and land in one table. Each fixture
# is a real response, trimmed, so what is asserted here is what the feeds
# actually say rather than what they were assumed to say.
class FetchEntriesTest < ActiveSupport::TestCase
  FACEBOOK_ENV = {
    "FB_PAGE_ID" => "166417243936",
    "FB_PAGE_TOKEN" => "page-token-for-tests"
  }.freeze

  setup do
    @environment = ENV.to_h.slice(*FACEBOOK_ENV.keys)
    ENV.update(FACEBOOK_ENV)
  end

  teardown do
    FACEBOOK_ENV.each_key { |key| ENV.delete(key) }
    ENV.update(@environment)
  end

  test "an event arrives with the free text that says where to turn up" do
    stub_source(FetchKktixEntriesJob::FEED_URL, "kktix_events.atom")

    FetchKktixEntriesJob.perform_now

    entry = Entry.kktix.find_by(external_id: "tag:rubytaiwan.kktix.cc,2005:Event/125160")
    assert_equal "Ruby Jam 2026/09 月場", entry.title
    assert_equal "https://rubytaiwan.kktix.cc/events/rubyjam2609", entry.url
    assert_equal 2026, entry.published_at.year
    assert_match "PicCafe", entry.metadata["schedule"]
    # This source has no image of any kind to offer.
    assert_nil entry.thumbnail_url
  end

  test "a recording keeps the thumbnail, because this source's URL survives" do
    stub_source(FetchYoutubeEntriesJob::FEED_URL, "youtube_videos.xml")

    FetchYoutubeEntriesJob.perform_now

    entry = Entry.youtube.find_by(external_id: "E5DvufDmmmI")
    assert_equal "https://i2.ytimg.com/vi/E5DvufDmmmI/hqdefault.jpg", entry.thumbnail_url
    assert_equal "https://www.youtube.com/watch?v=E5DvufDmmmI", entry.url
    assert_match "COSCUP", entry.summary
  end

  test "a post arrives without a title, because the source has none to give" do
    stub_source(facebook_url, "facebook_posts.json")

    FetchFacebookEntriesJob.perform_now

    entry = Entry.facebook.find_by(external_id: "166417243936_1477619374393392")
    assert_nil entry.title
    assert_match "COSCUP", entry.summary
    assert_equal "https://www.facebook.com/1482497060572290/posts/1477619374393392", entry.url
    # Kept out on purpose: this source's image URL expires days after it is
    # handed over, and nothing here comes back to refresh a row.
    assert_nil entry.thumbnail_url
  end

  test "a second day adds nothing the first already caught" do
    stub_source(FetchKktixEntriesJob::FEED_URL, "kktix_events.atom")

    FetchKktixEntriesJob.perform_now
    caught = Entry.count
    FetchKktixEntriesJob.perform_now

    assert_operator caught, :>, 0
    assert_equal caught, Entry.count
  end

  # A page whose data access has lapsed answers 400 like a malformed request
  # does, and only the reason tells the two apart — one needs a person to
  # re-authorise, the other needs a fix here.
  test "a refusal is logged with the reason the source gave for it" do
    stub_request(:get, facebook_url).to_return(
      status: 400,
      body: { error: { code: 190, error_subcode: 463, message: "Session has expired" } }.to_json
    )

    assert_logged(/answered 400 .*Session has expired/) { FetchFacebookEntriesJob.perform_now }

    assert_equal 0, Entry.count
  end

  test "a source that stops answering leaves the table as it was" do
    stub_request(:get, FetchYoutubeEntriesJob::FEED_URL).to_return(status: 503)

    assert_nothing_raised { FetchYoutubeEntriesJob.perform_now }

    assert_equal 0, Entry.count
  end

  # The shape this round is built to notice: a source answers, so nothing looks
  # broken, but there is nothing in the answer to read.
  test "an answer with nothing in it says so, rather than passing for quiet news" do
    stub_request(:get, FetchYoutubeEntriesJob::FEED_URL)
      .to_return(status: 200, body: "<html><body>Sign in to continue</body></html>")

    assert_logged(/held no entries/) { FetchYoutubeEntriesJob.perform_now }

    assert_equal 0, Entry.count
  end

  private

  def assert_logged(pattern)
    written = StringIO.new
    original = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(written)
    yield
    assert_match pattern, written.string
  ensure
    ActiveJob::Base.logger = original
  end

  def stub_source(url, fixture)
    stub_request(:get, url).to_return(
      status: 200,
      body: file_fixture(fixture).read
    )
  end

  def facebook_url
    "https://graph.facebook.com/#{FetchFacebookEntriesJob::GRAPH_VERSION}" \
      "/#{FACEBOOK_ENV["FB_PAGE_ID"]}/posts?fields=#{FetchFacebookEntriesJob::FIELDS}"
  end
end
