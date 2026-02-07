chcp 65001 | Out-Null

$OutputEncoding = [System.Text.Encoding]::UTF8

Set-Location $PSScriptRoot



function Get-Tarih {

    [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now,'Turkey Standard Time').ToString('yyyy-MM-dd HH:mm:ss')

}



function Bekle {

    Write-Host ""

    Write-Host "[Enter] Ana menuye don" -ForegroundColor DarkGray

    Read-Host

}

function Push-CurrentBranch {

    $currentBranch = git branch --show-current 2>$null

    $hasUpstream = $true

    if ($currentBranch) {

        git rev-parse --abbrev-ref --symbolic-full-name "@{u}" *> $null

        $hasUpstream = ($LASTEXITCODE -eq 0)

    }

    if ($hasUpstream) {

        git push

    } else {

        git push -u origin $currentBranch

    }

}



# Mevcut branch adini guvenli sekilde al (detached HEAD dahil)

function Get-Branch {

    $b = git branch --show-current 2>$null

    if ($b) { return $b }

    $desc = git describe --tags --exact-match 2>$null

    if ($desc) { return "($desc)" }

    $sha = git rev-parse --short HEAD 2>$null

    if ($sha) { return "(detached:$sha)" }

    return "?"

}



function DalListele {

    $mevcutDal = git branch --show-current 2>$null

    # Yerel dallar - detached HEAD satirini filtrele

    $yerelDallar = @(git branch 2>$null | ForEach-Object {

        $line = $_

        if ($line -match 'detached|HEAD detached') { return }

        ($line -replace '^\*?\s+','').Trim()

    } | Where-Object { $_ })



    # Remote dallar - "->" iceren satirlari ve yerel olanlari filtrele

    $uzakDallar = @(git branch -r 2>$null | ForEach-Object {

        $line = $_.Trim()

        if ($line -match '->') { return }

        $line -replace '^origin/',''

    } | Where-Object { $_ -and $_ -notin $yerelDallar })



    $tumDallar = @()

    Write-Host ""

    for ($i = 0; $i -lt $yerelDallar.Count; $i++) {

        $tumDallar += $yerelDallar[$i]

        if ($yerelDallar[$i] -eq $mevcutDal) {

            Write-Host "  $($i+1)) $($yerelDallar[$i]) " -NoNewline

            Write-Host "<- buradasin" -ForegroundColor Green

        } else {

            Write-Host "  $($i+1)) $($yerelDallar[$i])"

        }

    }

    if ($uzakDallar.Count -gt 0) {

        Write-Host ""

        Write-Host "  --- Sadece remote'ta ---" -ForegroundColor DarkGray

        for ($i = 0; $i -lt $uzakDallar.Count; $i++) {

            $no = $i + $yerelDallar.Count + 1

            $tumDallar += $uzakDallar[$i]

            Write-Host "  $no) " -NoNewline

            Write-Host "$($uzakDallar[$i]) (remote)" -ForegroundColor DarkGray

        }

    }

    Write-Host ""

    return ,@($tumDallar, $yerelDallar)

}



function DalSec {
    param([string]$mesaj, [array]$dallar)
    $s = Read-Host $mesaj
    $idx = 0
    if ([int]::TryParse($s, [ref]$idx) -and $idx -ge 1 -and $idx -le $dallar.Count) {

        return $dallar[$idx - 1]

    }

    if ($s) { Write-Host "Gecersiz secim!" -ForegroundColor Red }
    return $null
}

function Get-MainRef {
    $remoteMain = git show-ref --verify "refs/remotes/origin/main" 2>$null
    if ($LASTEXITCODE -eq 0 -and $remoteMain) { return "origin/main" }
    $localMain = git show-ref --verify "refs/heads/main" 2>$null
    if ($LASTEXITCODE -eq 0 -and $localMain) { return "main" }
    return $null
}

function Get-BranchRelation {
    param([string]$HeadRef, [string]$BaseRef)
    $raw = git rev-list --left-right --count "$BaseRef...$HeadRef" 2>$null
    if (-not $raw) { return $null }
    $parts = $raw -split '\s+'
    if ($parts.Count -lt 2) { return $null }
    return [PSCustomObject]@{
        Ahead  = [int]$parts[1]
        Behind = [int]$parts[0]
    }
}

function Show-CompareReport {
    param([string]$TargetRef, [string]$Label)
    if (-not $TargetRef) {
        Write-Host "Karsilastirma hedefi bulunamadi." -ForegroundColor Red
        return
    }

    $rel = Get-BranchRelation -HeadRef "HEAD" -BaseRef $TargetRef
    if ($rel) {
        Write-Host "Durum: Bu dal $Label karsisinda " -NoNewline
        Write-Host "$($rel.Ahead) ileri" -ForegroundColor Green -NoNewline
        Write-Host ", " -NoNewline
        Write-Host "$($rel.Behind) geri" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Dosya fark ozeti ($Label...HEAD):" -ForegroundColor White
    $stat = git diff --stat "$TargetRef...HEAD" 2>$null
    if (-not $stat) {
        Write-Host "Fark bulunamadi." -ForegroundColor Yellow
    } else {
        $stat
    }

    Write-Host ""
    Write-Host "Commit farklari (ilk 20):" -ForegroundColor White
    git log --oneline --left-right --cherry "$TargetRef...HEAD" -20 2>$null

    Write-Host ""
    Write-Host "Detayli diff acilsin mi? " -NoNewline
    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray
    $d = Read-Host
    if ($d -ne "h") {
        git diff "$TargetRef...HEAD"
    }
}

function Test-MergePasswordGuard {
    Write-Host "!!! UYARI !!! Bu menu otomatik merge calistirir." -ForegroundColor Red
    Write-Host "Yanlis secim conflict veya istenmeyen kod birlesimine neden olabilir." -ForegroundColor Yellow
    $sec = Read-Host "Sifreyi gir" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
    if ($plain -ne "benkaan") {
        Write-Host "Sifre hatali. Islem iptal edildi." -ForegroundColor Red
        return $false
    }
    return $true
}

function Merge-TargetIntoCurrent {
    param([string]$TargetRef, [string]$Label)
    $current = git branch --show-current 2>$null
    if (-not $current) {
        Write-Host "Detached HEAD durumunda merge engellendi." -ForegroundColor Red
        return $false
    }
    if ($TargetRef -eq $current -or $Label -eq $current) {
        Write-Host "Ayni dali kendisiyle birlestiremezsin: $current" -ForegroundColor Yellow
        return $false
    }

    if ($current -eq "main" -and ($TargetRef -eq "main" -or $TargetRef -eq "origin/main" -or $Label -eq "main" -or $Label -eq "origin/main")) {
        Write-Host "main -> main merge engellendi." -ForegroundColor Yellow
        return $false
    }

    $rel = Get-BranchRelation -HeadRef "HEAD" -BaseRef $TargetRef
    if ($rel) {
        Write-Host "Karsilastirma: $Label -> $current | " -NoNewline
        Write-Host "$($rel.Ahead) ileri" -ForegroundColor Green -NoNewline
        Write-Host ", " -NoNewline
        Write-Host "$($rel.Behind) geri" -ForegroundColor Yellow
    }

    $onay = Read-Host "Merge onayi icin 'evet' yazin ($Label -> $current)"
    if ($onay -ne "evet") {
        Write-Host "Iptal edildi."
        return $false
    }

    git merge $TargetRef
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Merge basarili: $Label -> $current" -ForegroundColor Green
        return $true
    }

    Write-Host ""
    Write-Host "Merge conflict olustu!" -ForegroundColor Red
    Write-Host "  1) git status ile conflict dosyalarini kontrol et" -ForegroundColor Yellow
    Write-Host "  2) Cozup git add . && git commit" -ForegroundColor Yellow
    Write-Host "  3) Iptal icin git merge --abort" -ForegroundColor Yellow
    return $false
}

function Show-MergePrecheckList {
    $current = git branch --show-current 2>$null
    if (-not $current) {
        Write-Host "Detached HEAD durumunda liste olusturulamadi." -ForegroundColor Red
        return
    }

    $mainRef = Get-MainRef
    Write-Host "Merge Oncesi Durum Listesi" -ForegroundColor White
    Write-Host "Referans dal: $current" -ForegroundColor DarkGray
    if ($mainRef) {
        Write-Host "Main referansi: $mainRef" -ForegroundColor DarkGray
    }
    Write-Host ""
    $fmt = "{0,-22} {1,-14} {2,-20} {3,-20}"
    Write-Host ($fmt -f "BRANCH", "SAHIP", "MEVCUDA GORE", "MAINE GORE")
    Write-Host ($fmt -f "------", "-----", "------------", "----------")

    $branches = git for-each-ref --format='%(refname:short)' refs/heads 2>$null
    foreach ($b in $branches) {
        if (-not $b) { continue }
        $owner = git log -1 --pretty=format:'%an' $b 2>$null
        if (-not $owner) { $owner = "-" }

        $curText = "-"
        $relCur = Get-BranchRelation -HeadRef $b -BaseRef "HEAD"
        if ($relCur) {
            $curText = "+$($relCur.Ahead) / -$($relCur.Behind)"
        }

        $mainText = "-"
        if ($mainRef) {
            $relMain = Get-BranchRelation -HeadRef $b -BaseRef $mainRef
            if ($relMain) {
                $mainText = "+$($relMain.Ahead) / -$($relMain.Behind)"
            }
        }

        Write-Host ($fmt -f $b, $owner, $curText, $mainText)
    }
}

function Merge-AllIntoMainAndPush {
    $startBranch = git branch --show-current 2>$null
    if (-not $startBranch) {
        Write-Host "Detached HEAD durumunda bu islem yapilamaz." -ForegroundColor Red
        return
    }

    $mainRef = Get-MainRef
    if (-not $mainRef) {
        Write-Host "main dali bulunamadi (ne local ne origin/main)." -ForegroundColor Red
        return
    }

    $hasLocalMain = git show-ref --verify "refs/heads/main" 2>$null
    if (-not $hasLocalMain -and $mainRef -eq "origin/main") {
        git checkout -b main origin/main
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Local main olusturulamadi." -ForegroundColor Red
            return
        }
    } else {
        git checkout main
        if ($LASTEXITCODE -ne 0) {
            Write-Host "main dalina gecilemedi." -ForegroundColor Red
            return
        }
    }

    Write-Host "!!! UYARI !!! Tum yerel branch'ler main'e merge edilecek." -ForegroundColor Red
    $onay = Read-Host "Onay icin 'evet' yazin"
    if ($onay -ne "evet") {
        Write-Host "Iptal edildi."
        return
    }

    $merged = 0
    $failed = 0
    $skipped = 0
    $branches = git for-each-ref --format='%(refname:short)' refs/heads 2>$null
    foreach ($b in $branches) {
        if (-not $b) { continue }
        if ($b -eq "main") {
            $skipped++
            Write-Host "Atlandi: main -> main merge yapilmaz." -ForegroundColor DarkGray
            continue
        }
        Write-Host ""
        Write-Host "Merge deneniyor: $b -> main" -ForegroundColor White
        $rel = Get-BranchRelation -HeadRef $b -BaseRef "main"
        if ($rel) {
            Write-Host "Durum: " -NoNewline
            Write-Host "+$($rel.Ahead)" -ForegroundColor Green -NoNewline
            Write-Host " / " -NoNewline
            Write-Host "-$($rel.Behind)" -ForegroundColor Yellow -NoNewline
            Write-Host " (main'e gore)"
        }
        git merge $b
        if ($LASTEXITCODE -eq 0) {
            $merged++
        } else {
            $failed++
            Write-Host "Conflict olustu, seri merge durduruldu: $b" -ForegroundColor Red
            break
        }
    }

    Write-Host ""
    Write-Host "Ozet: $merged merge, $skipped atlandi, $failed hata"
    Write-Host "main pushlansin mi? " -NoNewline
    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray
    $push = Read-Host
    if ($push -ne "h") {
        git push origin main
    }
}

function Sync-AllLocalBranches {
    $startBranch = git branch --show-current 2>$null
    if (-not $startBranch) {
        Write-Host "Detached HEAD durumunda bu islem yapilamaz." -ForegroundColor Red
        return
    }

    $dirty = git status --porcelain 2>$null
    if ($dirty) {
        Write-Host "Calisma alani temiz degil. Once commit/stash yap." -ForegroundColor Red
        return
    }

    Write-Host "!!! UYARI !!! Tum local branch'ler tek tek senkronize edilecek (pull --rebase)." -ForegroundColor Red
    $onay = Read-Host "Onay icin 'evet' yazin"
    if ($onay -ne "evet") {
        Write-Host "Iptal edildi."
        return
    }

    git fetch --all --prune
    $ok = 0
    $skip = 0
    $fail = 0
    $branches = git for-each-ref --format='%(refname:short)' refs/heads 2>$null
    foreach ($b in $branches) {
        if (-not $b) { continue }
        Write-Host ""
        Write-Host "Senkron: $b" -ForegroundColor White
        git checkout $b 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Branch'e gecilemedi: $b" -ForegroundColor Red
            $fail++
            break
        }

        $upstream = git rev-parse --abbrev-ref --symbolic-full-name "$b@{upstream}" 2>$null
        if (-not $upstream) {
            Write-Host "Upstream yok, atlandi." -ForegroundColor Yellow
            $skip++
            continue
        }

        $rel = Get-BranchRelation -HeadRef "HEAD" -BaseRef $upstream
        if ($rel) {
            Write-Host "Upstream: $upstream | " -NoNewline
            Write-Host "+$($rel.Ahead)" -ForegroundColor Green -NoNewline
            Write-Host " / " -NoNewline
            Write-Host "-$($rel.Behind)" -ForegroundColor Yellow
        }

        git pull --rebase
        if ($LASTEXITCODE -eq 0) {
            $ok++
        } else {
            Write-Host "Senkron hatasi: $b" -ForegroundColor Red
            $fail++
            break
        }
    }

    Write-Host ""
    Write-Host "Ozet: $ok basarili, $skip atlandi, $fail hata"
    git checkout $startBranch 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Baslangic branch'ine donuldu: $startBranch" -ForegroundColor DarkGray
    } else {
        Write-Host "Baslangic branch'ine otomatik donulemedi: $startBranch" -ForegroundColor Yellow
    }
}


function Kilavuz {

    Clear-Host

    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host "          KULLANIM KILAVUZU" -ForegroundColor Cyan

    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "TEMEL ISLEMLER" -ForegroundColor White

    Write-Host "--------------------------------------------" -ForegroundColor DarkGray

    Write-Host "Kaydet ve Gonder (1):" -ForegroundColor Green

    Write-Host "  Yaptigin degisiklikleri kaydeder ve GitHub'a gonderir."

    Write-Host "  Commit mesaji yazabilirsin, bos birakirsan tarih+isim kullanilir."

    Write-Host "  Ornek: 'Login ekrani eklendi | 2026-02-07 18:30:00 | kaan@PC'" -ForegroundColor DarkGray

    Write-Host ""

    Write-Host "Guncelle (2):" -ForegroundColor Green

    Write-Host "  GitHub'taki son degisiklikleri bilgisayarina indirir."

    Write-Host "  Baska birisi degisiklik yaptiysa bu secenekle cek."

    Write-Host ""

    Write-Host "Durum Gor (3):" -ForegroundColor Green

    Write-Host "  Hangi dosyalarin degistigini, eklendigini veya silindigini gosterir."

    Write-Host ""

    Write-Host "Gecmis Gor (4):" -ForegroundColor Green

    Write-Host "  Son 15 commit'i listeler. Kim, ne zaman, ne degistirmis gorursun."

    Write-Host ""

    Write-Host "Fark Analizi (5):" -ForegroundColor Green
    Write-Host "  Calisma alani, main veya secilen bir branch ile farklari gosterir."
    Write-Host ""

    Write-Host "DALLANMA (BRANCH)" -ForegroundColor White

    Write-Host "--------------------------------------------" -ForegroundColor DarkGray

    Write-Host "Dal Degistir (6):" -ForegroundColor Green

    Write-Host "  Numaraya basarak baska bir dala gecersin."

    Write-Host ""

    Write-Host "Yeni Dal Olustur (7):" -ForegroundColor Green

    Write-Host "  Yeni bir calisma dali acar. Ana kodu bozmadan deney yapabilirsin."

    Write-Host ""

    Write-Host "Dal Sil (8):" -ForegroundColor Green

    Write-Host "  Artik ihtiyac olmayan bir dali siler."

    Write-Host "  Dikkat: Uzerinde oldugun dali silemezsin, once baska dala gec."

    Write-Host ""

    Write-Host "Dal Birlestir (9):" -ForegroundColor Green

    Write-Host "  Baska bir daldaki degisiklikleri mevcut dalina aktarir."

    Write-Host ""

    Write-Host "DIGER" -ForegroundColor White

    Write-Host "--------------------------------------------" -ForegroundColor DarkGray

    Write-Host "Degisiklikleri Sakla (10):" -ForegroundColor Green

    Write-Host "  Yarim kalan isin varsa bir kenara koyar. Sonra geri alabilirsin."

    Write-Host ""

    Write-Host "Saklananlar Geri Al (11):" -ForegroundColor Green

    Write-Host "  Daha once sakladigin degisiklikleri geri getirir."

    Write-Host ""

    Write-Host "Geri Al (12):" -ForegroundColor Green

    Write-Host "  Yaptigin degisiklikleri iptal eder. Tek dosya veya hepsini geri alabilirsin."

    Write-Host "  Dikkat: Geri alinan degisiklikler kaybolur!" -ForegroundColor Yellow

    Write-Host ""

    Write-Host "Etiket Olustur (13):" -ForegroundColor Green

    Write-Host "  Surum numarasi ekler. Ornek: v1.0.0, v2.1.0"

    Write-Host ""

    Write-Host "Remote Bilgisi (14):" -ForegroundColor Green

    Write-Host "  Projenin bagli oldugu GitHub adresini gosterir."

    Write-Host ""

    Write-Host "Remote Guncelle (15):" -ForegroundColor Green
    Write-Host "  GitHub'taki tum dal bilgilerini gunceller (dosyalari degistirmez)."
    Write-Host ""
    Write-Host "Senkron ve Guncelle (16):" -ForegroundColor Green
    Write-Host "  Main ve upstream karsisinda kac commit ileri/geri oldugunu gosterir."
    Write-Host "  Buradan pull --rebase / main rebase / main merge hizli yapabilirsin."
    Write-Host ""
    Write-Host "Korumali Oto Merge (17):" -ForegroundColor Green
    Write-Host "  Uyari + sifre ister, sonra main veya secilen branch'leri otomatik merge eder."
    Write-Host "  Ayrica tum local branch'leri main'e merge edip pushlama secenegi vardir."
    Write-Host "  Istersen tum local branch'leri tek seferde senkronize de eder."
    Write-Host ""
    Write-Host "KISAYOLLAR" -ForegroundColor White

    Write-Host "--------------------------------------------" -ForegroundColor DarkGray

    Write-Host "  E veya Enter  = Evet (onay sorularinda)"

    Write-Host "  h             = Hayir (iptal)"

    Write-Host "  0             = Ana menuye / Cikis"

    Write-Host ""

    Bekle

}



$kullanici = $env:USERNAME

$bilgisayar = $env:COMPUTERNAME



while ($true) {

    $branch = Get-Branch

    $degisiklikSayisi = (git status --porcelain 2>$null | Measure-Object).Count



    Clear-Host

    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host "          GIT YONETIM PANELI" -ForegroundColor Cyan

    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host "  Repo     : $(Split-Path -Leaf $PSScriptRoot)"

    Write-Host "  Branch   : " -NoNewline; Write-Host "$branch" -ForegroundColor Green

    Write-Host "  Kullanici: $kullanici@$bilgisayar"

    if ($degisiklikSayisi -gt 0) {

        Write-Host "  Bekleyen : " -NoNewline; Write-Host "$degisiklikSayisi degisiklik" -ForegroundColor Yellow

    } else {

        Write-Host "  Bekleyen : Temiz"

    }

    $actualBranch = git branch --show-current 2>$null
    if ($actualBranch) {
        $upstream = git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>$null
        if ($upstream) {
            $relUp = Get-BranchRelation -HeadRef "HEAD" -BaseRef $upstream
            if ($relUp) {
                Write-Host "  Upstream : $upstream (" -NoNewline
                Write-Host "$($relUp.Ahead) ileri" -ForegroundColor Green -NoNewline
                Write-Host ", " -NoNewline
                Write-Host "$($relUp.Behind) geri" -ForegroundColor Yellow -NoNewline
                Write-Host ")"
            }
        }

        $mainRef = Get-MainRef
        if ($mainRef -and $actualBranch -ne "main") {
            $relMain = Get-BranchRelation -HeadRef "HEAD" -BaseRef $mainRef
            if ($relMain) {
                Write-Host "  Main fark: " -NoNewline
                Write-Host "$($relMain.Ahead) ileri" -ForegroundColor Green -NoNewline
                Write-Host ", " -NoNewline
                Write-Host "$($relMain.Behind) geri" -ForegroundColor Yellow
                if ($relMain.Behind -gt 0) {
                    Write-Host "  UYARI: $mainRef dalindan $($relMain.Behind) commit geridesin." -ForegroundColor Red
                    Write-Host "  (Hizli guncelle: 16)" -ForegroundColor DarkGray
                }
            }
        }
    }
    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  --- TEMEL ISLEMLER ---" -ForegroundColor White

    Write-Host "  1)  Kaydet ve Gonder    " -NoNewline; Write-Host "(commit & push)" -ForegroundColor DarkGray

    Write-Host "  2)  Guncelle             " -NoNewline; Write-Host "(pull)" -ForegroundColor DarkGray

    Write-Host "  3)  Durum Gor            " -NoNewline; Write-Host "(status)" -ForegroundColor DarkGray

    Write-Host "  4)  Gecmis Gor           " -NoNewline; Write-Host "(log)" -ForegroundColor DarkGray

    Write-Host "  5)  Fark Analizi         " -NoNewline; Write-Host "(calisma/main/dal)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  --- DALLANMA (BRANCH) ---" -ForegroundColor White

    Write-Host "  6)  Dal Degistir         " -NoNewline; Write-Host "(checkout)" -ForegroundColor DarkGray

    Write-Host "  7)  Yeni Dal Olustur     " -NoNewline; Write-Host "(new branch)" -ForegroundColor DarkGray

    Write-Host "  8)  Dal Sil              " -NoNewline; Write-Host "(delete branch)" -ForegroundColor DarkGray

    Write-Host "  9)  Dal Birlestir        " -NoNewline; Write-Host "(merge)" -ForegroundColor DarkGray

    Write-Host ""

    Write-Host "  --- DIGER ---" -ForegroundColor White

    Write-Host "  10) Degisiklikleri Sakla  " -NoNewline; Write-Host "(stash)" -ForegroundColor DarkGray

    Write-Host "  11) Saklananlar Geri Al  " -NoNewline; Write-Host "(stash pop)" -ForegroundColor DarkGray

    Write-Host "  12) Geri Al              " -NoNewline; Write-Host "(restore)" -ForegroundColor DarkGray

    Write-Host "  13) Etiket Olustur       " -NoNewline; Write-Host "(tag)" -ForegroundColor DarkGray

    Write-Host "  14) Remote Bilgisi"

    Write-Host "  15) Remote Guncelle      " -NoNewline; Write-Host "(fetch)" -ForegroundColor DarkGray
    Write-Host "  16) Senkron ve Guncelle  " -NoNewline; Write-Host "(main/upstream menusu)" -ForegroundColor DarkGray
    Write-Host "  17) Korumali Oto Merge   " -NoNewline; Write-Host "(sifreli merge menusu)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  ?)  Kullanim Kilavuzu" -ForegroundColor Yellow

    Write-Host "  0)  Cikis" -ForegroundColor Red

    Write-Host ""

    $secim = Read-Host "  Secimin"



    switch ($secim) {

        "1" {

            Clear-Host

            Write-Host "=== KAYDET VE GONDER ===" -ForegroundColor Green

            Write-Host ""

            git status -s

            Write-Host ""

            $durum = git status --porcelain

            if (-not $durum) {

                Write-Host "Kaydedilecek degisiklik yok." -ForegroundColor Yellow

                Bekle; continue

            }

            Write-Host "Commit mesaji yazin " -NoNewline

            Write-Host "(bos birakirsan tarih+isim kullanilir)" -ForegroundColor DarkGray

            $aciklama = Read-Host

            $tarih = Get-Tarih

            if ([string]::IsNullOrWhiteSpace($aciklama)) {

                $mesaj = "$tarih | $kullanici@$bilgisayar"

            } else {

                $mesaj = "$aciklama | $tarih | $kullanici@$bilgisayar"

            }

            git add -A

            git commit -m "$mesaj"

            if ($LASTEXITCODE -ne 0) {

                Write-Host "Commit basarisiz oldu!" -ForegroundColor Red

                Bekle; continue

            }

            Write-Host ""

            Write-Host "GitHub'a gonderilsin mi? " -NoNewline

            Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

            $push = Read-Host

            if ($push -ne "h" -and $push -ne "H") {

                Push-CurrentBranch

                if ($LASTEXITCODE -ne 0) {

                    Write-Host ""

                    Write-Host "Push basarisiz. Remote ilerideyse 'pull --rebase' denensin mi? " -NoNewline

                    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                    $retry = Read-Host

                    if ($retry -ne "h" -and $retry -ne "H") {

                        git pull --rebase

                        Push-CurrentBranch

                    }

                }

            }

            Write-Host ""

            Write-Host "Kaydedildi: $mesaj" -ForegroundColor Green

            Bekle

        }

        "2" {

            Clear-Host

            Write-Host "=== GUNCELLE (PULL) ===" -ForegroundColor Green

            Write-Host ""

            git pull

            if ($LASTEXITCODE -ne 0) {

                Write-Host ""

                Write-Host "Pull basarisiz oldu. Conflict olabilir, 'git status' ile kontrol edin." -ForegroundColor Red

            }

            Bekle

        }

        "3" {

            Clear-Host

            Write-Host "=== DURUM ===" -ForegroundColor Green

            Write-Host ""

            git status

            Bekle

        }

        "4" {

            Clear-Host

            Write-Host "=== SON 15 COMMIT ===" -ForegroundColor Green

            Write-Host ""

            git log --oneline --graph --decorate -15

            Bekle

        }

        "5" {
            Clear-Host
            Write-Host "=== FARK ANALIZI ===" -ForegroundColor Green
            Write-Host ""
            Write-Host "  1) Calisma alanini goster (unstaged/staged)"
            Write-Host "  2) main ile farki goster"
            Write-Host "  3) Secilen branch ile farki goster"
            Write-Host ""
            $altDiff = Read-Host "  Secimin"

            if ($altDiff -eq "1") {
                $diffStat = git diff --stat 2>$null
                $diffCached = git diff --cached --stat 2>$null
                if (-not $diffStat -and -not $diffCached) {
                    Write-Host "Gosterilecek fark yok." -ForegroundColor Yellow
                } else {
                    if ($diffStat) { $diffStat }
                    if ($diffCached) {
                        Write-Host ""
                        Write-Host "(staged degisiklikler)" -ForegroundColor DarkGray
                        $diffCached
                    }
                    Write-Host ""
                    Write-Host "Detayli gormek ister misin? " -NoNewline
                    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray
                    $d = Read-Host
                    if ($d -ne "h") {
                        git diff
                        git diff --cached
                    }
                }
            } elseif ($altDiff -eq "2") {
                $mainRef = Get-MainRef
                if (-not $mainRef) {
                    Write-Host "main dali bulunamadi (ne local ne origin/main)." -ForegroundColor Red
                } else {
                    Show-CompareReport -TargetRef $mainRef -Label $mainRef
                }
            } elseif ($altDiff -eq "3") {
                git fetch --prune 2>$null
                $sonuc = DalListele
                $tumDallar = $sonuc[0]
                $yerelDallar = $sonuc[1]
                $hedef = DalSec -mesaj "  Karsilastirmak istedigin dal (numara)" -dallar $tumDallar
                if ($hedef) {
                    $targetRef = $hedef
                    if ($yerelDallar -notcontains $hedef) {
                        $targetRef = "origin/$hedef"
                    }
                    Show-CompareReport -TargetRef $targetRef -Label $targetRef
                }
            } else {
                Write-Host "Islem iptal edildi." -ForegroundColor Yellow
            }
            Bekle
        }
        "6" {

            Clear-Host

            Write-Host "=== DAL DEGISTIR ===" -ForegroundColor Green

            # Oncelikle remote bilgilerini guncelle

            git fetch --prune 2>$null

            $sonuc = DalListele

            $tumDallar = $sonuc[0]

            $yerelDallar = $sonuc[1]

            $hedef = DalSec -mesaj "  Gecmek istedigin dal (numara)" -dallar $tumDallar

            if ($hedef) {

                # Remote-only mu kontrol et

                if ($yerelDallar -contains $hedef) {

                    git checkout $hedef

                } else {

                    # Remote-only: tracking branch olarak olustur

                    $yerelVar = git show-ref --verify "refs/heads/$hedef" 2>$null

                    if ($yerelVar) {

                        git checkout $hedef

                    } else {

                        git checkout -b $hedef "origin/$hedef"

                    }

                }

                if ($LASTEXITCODE -eq 0) {

                    Write-Host "Dal degistirildi: $(Get-Branch)" -ForegroundColor Green

                } else {

                    Write-Host "Dal degistirilemedi!" -ForegroundColor Red

                }

            }

            Bekle

        }

        "7" {

            Clear-Host

            Write-Host "=== YENI DAL OLUSTUR ===" -ForegroundColor Green

            Write-Host ""

            $yeni = Read-Host "Yeni dal adi"

            if ($yeni) {

                # Dal zaten var mi kontrol et

                $varMi = git show-ref --verify "refs/heads/$yeni" 2>$null

                if ($varMi) {

                    Write-Host "Bu isimde bir dal zaten var!" -ForegroundColor Red

                } else {

                    git checkout -b $yeni

                    Write-Host ""

                    Write-Host "GitHub'a gonderilsin mi? " -NoNewline

                    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                    $p = Read-Host

                    if ($p -ne "h") { git push -u origin $yeni }

                }

            }

            Bekle

        }

        "8" {

            Clear-Host

            Write-Host "=== DAL SIL ===" -ForegroundColor Green

            $sonuc = DalListele

            $tumDallar = $sonuc[0]

            $sil = DalSec -mesaj "  Silinecek dal (numara)" -dallar $tumDallar

            if ($sil) {

                $mevcutDal = git branch --show-current 2>$null

                if ($sil -eq $mevcutDal) {

                    Write-Host "Uzerinde oldugun dali silemezsin! Once baska dala gec." -ForegroundColor Red

                } else {

                    Write-Host "Emin misin? " -NoNewline

                    Write-Host "'$sil'" -ForegroundColor Red -NoNewline

                    Write-Host " silinecek " -NoNewline

                    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                    $onay = Read-Host

                    if ($onay -ne "h") {

                        git branch -d $sil 2>$null

                        if ($LASTEXITCODE -ne 0) {

                            Write-Host "Dal merge edilmemis. Yine de silinsin mi? " -NoNewline

                            Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                            $zorla = Read-Host

                            if ($zorla -ne "h") { git branch -D $sil }

                        }

                        Write-Host "GitHub'tan da silinsin mi? " -NoNewline

                        Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                        $r = Read-Host

                        if ($r -ne "h") { git push origin --delete $sil 2>$null }

                    }

                }

            }

            Bekle

        }

        "9" {

            Clear-Host

            Write-Host "=== DAL BIRLESTIR (MERGE) ===" -ForegroundColor Green

            Write-Host ""

            $mevcutDal = git branch --show-current 2>$null

            if (-not $mevcutDal) {

                Write-Host "Detached HEAD durumundasin. Once bir dala gec (6)." -ForegroundColor Red

                Bekle; continue

            }

            Write-Host "Mevcut dal: " -NoNewline; Write-Host "$mevcutDal" -ForegroundColor White

            $sonuc = DalListele

            $tumDallar = $sonuc[0]

            $mb = DalSec -mesaj "  '$mevcutDal' uzerine hangi dali birlestirmek istiyorsun (numara)" -dallar $tumDallar

            if ($mb) {

                if ($mb -eq $mevcutDal) {

                    Write-Host "Bir dali kendisiyle birlestiremezsin!" -ForegroundColor Red

                } else {

                    git merge $mb

                    if ($LASTEXITCODE -ne 0) {

                        Write-Host ""

                        Write-Host "Merge conflict olustu! Cozum secenekleri:" -ForegroundColor Red

                        Write-Host "  1) 'git status' ile conflict olan dosyalari gor" -ForegroundColor Yellow

                        Write-Host "  2) Dosyalari duzenle, sonra 'git add . && git commit'" -ForegroundColor Yellow

                        Write-Host "  3) Merge'i iptal etmek icin: 'git merge --abort'" -ForegroundColor Yellow

                    } else {

                        Write-Host "Merge basarili!" -ForegroundColor Green

                    }

                }

            }

            Bekle

        }

        "10" {

            Clear-Host

            Write-Host "=== DEGISIKLIKLERI SAKLA (STASH) ===" -ForegroundColor Green

            Write-Host ""

            $durum = git status --porcelain 2>$null

            if (-not $durum) {

                Write-Host "Saklanacak degisiklik yok." -ForegroundColor Yellow

                Bekle; continue

            }

            Write-Host "Stash mesaji " -NoNewline

            Write-Host "(bos birakirsan otomatik)" -ForegroundColor DarkGray

            $sm = Read-Host

            if ([string]::IsNullOrWhiteSpace($sm)) {

                git stash

            } else {

                git stash push -m "$sm"

            }

            Write-Host "Degisiklikler saklandi." -ForegroundColor Green

            Bekle

        }

        "11" {

            Clear-Host

            Write-Host "=== SAKLANANLARI GERI AL (STASH POP) ===" -ForegroundColor Green

            Write-Host ""

            $stashList = git stash list 2>$null

            if (-not $stashList) {

                Write-Host "Saklanan degisiklik yok." -ForegroundColor Yellow

                Bekle; continue

            }

            Write-Host "Saklanan degisiklikler:"

            $stashList

            Write-Host ""

            Write-Host "Geri alinsin mi? " -NoNewline

            Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

            $onay = Read-Host

            if ($onay -ne "h") {

                git stash pop

                if ($LASTEXITCODE -ne 0) {

                    Write-Host "Stash pop basarisiz! Conflict olabilir." -ForegroundColor Red

                }

            }

            Bekle

        }

        "12" {

            Clear-Host

            Write-Host "=== GERI AL (RESTORE) ===" -ForegroundColor Green

            Write-Host ""

            $durum = git status --porcelain 2>$null

            if (-not $durum) {

                Write-Host "Geri alinacak degisiklik yok." -ForegroundColor Yellow

                Bekle; continue

            }

            git status -s

            Write-Host ""

            Write-Host "  1) Tek dosya geri al"

            Write-Host "  2) Tum degisiklikleri geri al"

            Write-Host ""

            $alt = Read-Host "  Secimin"

            if ($alt -eq "1") {

                $dosya = Read-Host "Dosya adi"

                if ($dosya) {

                    git checkout -- $dosya 2>$null

                    if ($LASTEXITCODE -eq 0) {

                        Write-Host "Geri alindi: $dosya" -ForegroundColor Green

                    } else {

                        Write-Host "Dosya bulunamadi veya geri alinamadi: $dosya" -ForegroundColor Red

                    }

                }

            } elseif ($alt -eq "2") {

                Write-Host "UYARI: Tum degisiklikler kaybolacak!" -ForegroundColor Red

                $onay = Read-Host "Emin misin? ('evet' yazin)"

                if ($onay -eq "evet") {

                    git checkout -- .

                    git clean -fd 2>$null

                    Write-Host "Tum degisiklikler geri alindi." -ForegroundColor Green

                } else {

                    Write-Host "Iptal edildi."

                }

            }

            Bekle

        }

        "13" {

            Clear-Host

            Write-Host "=== ETIKET OLUSTUR (TAG) ===" -ForegroundColor Green

            Write-Host ""

            Write-Host "Mevcut etiketler:"

            $tags = git tag 2>$null

            if (-not $tags) {

                Write-Host "  (henuz etiket yok)" -ForegroundColor DarkGray

            } else {

                $tags

            }

            Write-Host ""

            $tag = Read-Host "Etiket adi (orn: v1.0.0)"

            if ($tag) {

                # Ayni etiket var mi kontrol et

                $mevcutTag = git tag -l $tag 2>$null

                if ($mevcutTag) {

                    Write-Host "Bu etiket zaten var!" -ForegroundColor Red

                } else {

                    Write-Host "Etiket mesaji " -NoNewline

                    Write-Host "(bos birakirsan basit etiket)" -ForegroundColor DarkGray

                    $tm = Read-Host

                    if ([string]::IsNullOrWhiteSpace($tm)) {

                        git tag $tag

                    } else {

                        git tag -a $tag -m "$tm"

                    }

                    Write-Host "Etiket olusturuldu: $tag" -ForegroundColor Green

                    Write-Host "GitHub'a gonderilsin mi? " -NoNewline

                    Write-Host "[Enter=Evet / h=Hayir]" -ForegroundColor DarkGray

                    $p = Read-Host

                    if ($p -ne "h") { git push origin $tag }

                }

            }

            Bekle

        }

        "14" {

            Clear-Host

            Write-Host "=== REMOTE BILGISI ===" -ForegroundColor Green

            Write-Host ""

            git remote -v

            Bekle

        }

        "15" {
            Clear-Host
            Write-Host "=== REMOTE GUNCELLE (FETCH) ===" -ForegroundColor Green
            Write-Host ""
            git fetch --all --prune
            Write-Host "Remote bilgileri guncellendi." -ForegroundColor Green
            Bekle
        }
        "16" {
            Clear-Host
            Write-Host "=== SENKRON VE GUNCELLE MENUSU ===" -ForegroundColor Green
            Write-Host ""
            git fetch --all --prune
            $current = git branch --show-current 2>$null
            if (-not $current) {
                Write-Host "Detached HEAD durumundasin. Once bir dala gec (6)." -ForegroundColor Red
                Bekle
                continue
            }

            Write-Host "Mevcut dal: " -NoNewline
            Write-Host "$current" -ForegroundColor White

            $upstream = git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>$null
            if ($upstream) {
                $relUp = Get-BranchRelation -HeadRef "HEAD" -BaseRef $upstream
                if ($relUp) {
                    Write-Host "Upstream: $upstream (" -NoNewline
                    Write-Host "$($relUp.Ahead) ileri" -ForegroundColor Green -NoNewline
                    Write-Host ", " -NoNewline
                    Write-Host "$($relUp.Behind) geri" -ForegroundColor Yellow -NoNewline
                    Write-Host ")"
                }
            } else {
                Write-Host "Bu dalin upstream'i tanimli degil." -ForegroundColor Yellow
            }

            $mainRef = Get-MainRef
            if ($mainRef) {
                $relMain = Get-BranchRelation -HeadRef "HEAD" -BaseRef $mainRef
                if ($relMain) {
                    Write-Host "Main fark: $mainRef (" -NoNewline
                    Write-Host "$($relMain.Ahead) ileri" -ForegroundColor Green -NoNewline
                    Write-Host ", " -NoNewline
                    Write-Host "$($relMain.Behind) geri" -ForegroundColor Yellow -NoNewline
                    Write-Host ")"
                }
            }

            Write-Host ""
            Write-Host "  1) Upstream'den pull --rebase"
            Write-Host "  2) main degisikliklerini rebase et"
            Write-Host "  3) main degisikliklerini merge et"
            Write-Host "  4) Sadece fetch yenile"
            Write-Host "  0) Geri"
            Write-Host ""
            $syncSecim = Read-Host "  Secimin"
            if ($syncSecim -eq "1") {
                git pull --rebase
            } elseif ($syncSecim -eq "2") {
                if ($mainRef) {
                    git rebase $mainRef
                } else {
                    Write-Host "main dali bulunamadi." -ForegroundColor Red
                }
            } elseif ($syncSecim -eq "3") {
                if ($mainRef) {
                    git merge $mainRef
                } else {
                    Write-Host "main dali bulunamadi." -ForegroundColor Red
                }
            } elseif ($syncSecim -eq "4") {
                git fetch --all --prune
            }
            Bekle
        }
        "17" {
            Clear-Host
            Write-Host "=== KORUMALI OTOMATIK MERGE ===" -ForegroundColor Green
            Write-Host ""
            if (-not (Test-MergePasswordGuard)) {
                Bekle
                continue
            }

            $current = git branch --show-current 2>$null
            if (-not $current) {
                Write-Host "Detached HEAD durumundasin. Once bir dala gec (6)." -ForegroundColor Red
                Bekle
                continue
            }

            git fetch --all --prune
            Write-Host "Mevcut dal: " -NoNewline
            Write-Host "$current" -ForegroundColor White
            Write-Host ""
            Write-Host "  1) main'i mevcut dala merge et"
            Write-Host "  2) Secilen tek dali mevcut dala merge et"
            Write-Host "  3) Birden fazla dali sirayla merge et"
            Write-Host "  4) Merge oncesi ileri/geri listesi (ad ile)"
            Write-Host "  5) Tum local branch'leri main'e merge et + push"
            Write-Host "  6) Tum local branch'leri senkronize et"
            Write-Host "  0) Geri"
            Write-Host ""
            $msecim = Read-Host "  Secimin"

            if ($msecim -eq "1") {
                $mainRef = Get-MainRef
                if (-not $mainRef) {
                    Write-Host "main dali bulunamadi." -ForegroundColor Red
                } else {
                    [void](Merge-TargetIntoCurrent -TargetRef $mainRef -Label $mainRef)
                }
            } elseif ($msecim -eq "2") {
                $sonuc = DalListele
                $tumDallar = $sonuc[0]
                $yerelDallar = $sonuc[1]
                $hedef = DalSec -mesaj "  Merge etmek istedigin dal (numara)" -dallar $tumDallar
                if ($hedef) {
                    $targetRef = $hedef
                    if ($yerelDallar -notcontains $hedef) {
                        $targetRef = "origin/$hedef"
                    }
                    [void](Merge-TargetIntoCurrent -TargetRef $targetRef -Label $targetRef)
                }
            } elseif ($msecim -eq "3") {
                $sonuc = DalListele
                $tumDallar = $sonuc[0]
                $yerelDallar = $sonuc[1]
                $coklu = Read-Host "Virgulle numara gir (orn: 2,4,5)"
                if ($coklu) {
                    $parcalar = $coklu -split ','
                    foreach ($raw in $parcalar) {
                        $idxText = $raw.Trim()
                        $idx = 0
                        if (-not [int]::TryParse($idxText, [ref]$idx) -or $idx -lt 1 -or $idx -gt $tumDallar.Count) {
                            Write-Host "Atlandi (gecersiz secim): $raw" -ForegroundColor Yellow
                            continue
                        }
                        $pick = $tumDallar[$idx - 1]
                        $targetRef = $pick
                        if ($yerelDallar -notcontains $pick) {
                            $targetRef = "origin/$pick"
                        }
                        $ok = Merge-TargetIntoCurrent -TargetRef $targetRef -Label $targetRef
                        if (-not $ok) {
                            Write-Host "Sirali merge durduruldu." -ForegroundColor Yellow
                            break
                        }
                    }
                }
            } elseif ($msecim -eq "4") {
                Show-MergePrecheckList
            } elseif ($msecim -eq "5") {
                Merge-AllIntoMainAndPush
            } elseif ($msecim -eq "6") {
                Sync-AllLocalBranches
            }
            Bekle
        }
        "?" {
            Kilavuz
        }
        "0" {

            Write-Host ""

            Write-Host "Gorusuruz!"

            exit

        }

        default {

            Write-Host "Gecersiz secim!" -ForegroundColor Red

            Bekle

        }

    }

}

