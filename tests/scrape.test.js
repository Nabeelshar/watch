import test from 'node:test';
import assert from 'node:assert/strict';
import { extractIframeSrc, extractNextEpisode, extractEpisodeKey, extractPageTitle, parseMedia } from '../server/media.js';

const PAGE = `
<html>
  <head>
    <meta property="og:title" content="BLACK TORCH 1x1" />
  </head>
  <body>
    <iframe src="https://piratexplay.cc/proxy/play.php?url=https://as-cdn26.top/video/5f22e82f3d2c279d57c76a0513276abb" frameborder="0" scrolling="no" allow="autoplay; encrypted-media" allowfullscreen=""></iframe>
    <div class="mb-30">
      <div class="epsdsnv mab1">
        <div>
          <a href="/series/black-torch-season-1-285993/" class="tertiary-bg mar"><i class="fa-indent"></i><span>Season</span></a>
        </div>
        <div style="display:flex;gap:.5rem;">
          <a class="aa-mdl tertiary-bg mar on" id="open-download" tab="ln0"><i class="fa-cloud-download-alt"></i></a>
          <!-- PREV -->
          <!-- NEXT -->
          <a href="/episode/black-torch-season-1-285993-1x2/" class="tertiary-bg mar"><svg xmlns="http://www.w3.org/2000/svg"></svg></a>
        </div>
      </div>
    </div>
    <section class="section episodes">
      <ul id="episode_by_temp" class="post-lst">
        <li><a href="/episode/black-torch-season-1-285993-1x1/" class="lnk-blk"></a></li>
        <li><a href="/episode/black-torch-season-1-285993-1x2/" class="lnk-blk"></a></li>
      </ul>
    </section>
  </body>
</html>`;

const EPISODE = 'https://piratexplay.cc/episode/black-torch-season-1-285993-1x1/';

test('episode key extraction', () => {
  assert.deepEqual(extractEpisodeKey('/episode/black-torch-season-1-285993-1x1/'), { season: 1, episode: 1 });
  assert.deepEqual(extractEpisodeKey('/episode/show-3-42-2x10/'), { season: 2, episode: 10 });
  assert.equal(extractEpisodeKey('/series/black-torch-season-1-285993/'), null);
});

test('iframe embed extraction prefers proxy/play.php and resolves the full URL', () => {
  assert.equal(extractIframeSrc(PAGE, EPISODE), 'https://piratexplay.cc/proxy/play.php?url=https://as-cdn26.top/video/5f22e82f3d2c279d57c76a0513276abb');
  assert.equal(extractIframeSrc('<p>no frames</p>', EPISODE), null);
  assert.equal(extractIframeSrc('<iframe src="/proxy/play.php?url=https%3A%2F%2Fx.test%2Fv%2Fabc"></iframe>', EPISODE), 'https://piratexplay.cc/proxy/play.php?url=https%3A%2F%2Fx.test%2Fv%2Fabc');
});

test('next episode link is resolved from the current season/episode', () => {
  assert.equal(extractNextEpisode(PAGE, EPISODE), 'https://piratexplay.cc/episode/black-torch-season-1-285993-1x2/');
  assert.equal(extractNextEpisode(PAGE, 'https://piratexplay.cc/episode/black-torch-season-1-285993-1x2/'), null);
});

test('page title extraction', () => {
  assert.equal(extractPageTitle(PAGE), 'BLACK TORCH 1x1');
  assert.equal(extractPageTitle('<h1>My Show</h1>'), 'My Show');
  assert.equal(extractPageTitle('<div>nothing</div>'), null);
});

test('Google Drive links normalize to preview embeds', () => {
  assert.equal(parseMedia('https://drive.google.com/file/d/1AbCdefGhIjKlMn/view').provider, 'Drive');
  assert.equal(parseMedia('https://drive.google.com/file/d/1AbCdefGhIjKlMn/view').url, 'https://drive.google.com/file/d/1AbCdefGhIjKlMn/preview');
  assert.equal(parseMedia('https://drive.google.com/open?id=XYZ123').url, 'https://drive.google.com/file/d/XYZ123/preview');
  assert.equal(parseMedia('https://drive.google.com/uc?id=XYZ123&export=download').url, 'https://drive.google.com/file/d/XYZ123/preview');
  assert.throws(() => parseMedia('https://drive.google.com/drive/u/0/my-drive'));
});
