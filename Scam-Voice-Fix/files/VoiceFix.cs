using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Drawing;
using System.Diagnostics;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Web.Script.Serialization;

namespace ScamVoiceFix {
    public sealed class LanguagePicker : Panel {
        readonly Button english,russian;
        int selected=-1;
        public event EventHandler SelectedIndexChanged;
        public int SelectedIndex {
            get{return selected;}
            set{if(selected==value)return;selected=value;RefreshStyle();if(SelectedIndexChanged!=null)SelectedIndexChanged(this,EventArgs.Empty);}
        }
        public LanguagePicker(){
            english=MakeButton("English");russian=MakeButton("Русский");
            english.Click+=delegate{SelectedIndex=0;};russian.Click+=delegate{SelectedIndex=1;};
            english.TabIndex=0;russian.TabIndex=1;
            Controls.Add(english);Controls.Add(russian);
            SizeChanged+=delegate{english.SetBounds(0,0,Width/2,Height);russian.SetBounds(Width/2,0,Width-Width/2,Height);};
            EnabledChanged+=delegate{RefreshStyle();};
        }
        Button MakeButton(string text){
            var button=new Button{Text=text,FlatStyle=FlatStyle.Flat,Font=new Font("Segoe UI",9.5f),Cursor=Cursors.Hand};
            button.FlatAppearance.BorderSize=1;button.FlatAppearance.BorderColor=Color.FromArgb(208,218,234);
            return button;
        }
        void RefreshStyle(){
            foreach(var pair in new[]{new{Button=english,Index=0},new{Button=russian,Index=1}}){
                pair.Button.BackColor=selected==pair.Index?Color.FromArgb(37,88,219):Color.White;
                pair.Button.ForeColor=selected==pair.Index?Color.White:Color.FromArgb(24,34,52);
            }
        }
    }
    public sealed class VoiceForm : Form {
        readonly string root;
        readonly Color ink=Color.FromArgb(24,34,52), muted=Color.FromArgb(93,106,126), blue=Color.FromArgb(37,88,219);
        readonly Color green=Color.FromArgb(26,124,77), amber=Color.FromArgb(157,92,12);
        Label brand,headline,subtitle,statusTitle,message,stage,elapsed,changes,compatibility;
        LanguagePicker language;
        Button fix,undo;
        LinkLabel check,details,help;
        Panel card;
        ProgressBar progress;
        System.Windows.Forms.Timer timer;
        Process worker;
        readonly ConcurrentQueue<string> lines=new ConcurrentQueue<string>();
        readonly StringBuilder log=new StringBuilder();
        Stopwatch clock;
        string resultPath,action,currentStage="",lastOutcome="",lastMessage="";
        bool busy,completed,closeRequested;
        bool Ru { get { return language.SelectedIndex==1; } }
        string T(string en,string ru){return Ru?ru:en;}

        public VoiceForm(string packageRoot){
            root=packageRoot;
            Text="Scam Voice Fix";
            StartPosition=FormStartPosition.CenterScreen;
            AutoScaleDimensions=new SizeF(96,96);AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(700,665);MinimumSize=new Size(660,690);
            Font=new Font("Segoe UI",10.5f);
            BackColor=Color.FromArgb(244,246,250);ForeColor=ink;
            MaximizeBox=false;
            brand=LabelAt(this,"SCAM WITH YOUR FRIENDS",24,24,450,22,10,FontStyle.Bold);
            brand.ForeColor=muted;
            language=new LanguagePicker {Location=new Point(488,20),Size=new Size(188,32),Anchor=AnchorStyles.Top|AnchorStyles.Right,TabIndex=0};
            Controls.Add(language);
            headline=LabelAt(this,"",24,58,652,51,24,FontStyle.Bold);
            subtitle=LabelAt(this,"",24,113,652,30,10.5f,FontStyle.Regular);subtitle.ForeColor=muted;
            card=new Panel{Location=new Point(24,152),Size=new Size(652,340),BackColor=Color.White,Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right};
            card.Paint+=delegate(object sender,PaintEventArgs e){using(var pen=new Pen(Color.FromArgb(224,230,239)))e.Graphics.DrawRectangle(pen,0,0,card.Width-1,card.Height-1);};
            Controls.Add(card);
            statusTitle=LabelAt(card,"",24,22,604,34,16,FontStyle.Bold);
            message=LabelAt(card,"",24,64,604,126,11,FontStyle.Regular);
            message.ForeColor=muted;
            progress=new ProgressBar{Location=new Point(24,197),Size=new Size(604,8),Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,Style=ProgressBarStyle.Marquee,MarqueeAnimationSpeed=30,Visible=false};
            card.Controls.Add(progress);
            stage=LabelAt(card,"",24,216,604,25,10.5f,FontStyle.Bold);
            elapsed=LabelAt(card,"",24,247,604,20,9.5f,FontStyle.Regular);elapsed.ForeColor=muted;
            fix=ButtonAt(card,"",24,282,350,44,true);fix.TabIndex=1;
            undo=ButtonAt(card,"",390,282,238,44,false);undo.TabIndex=2;undo.Anchor=AnchorStyles.Top|AnchorStyles.Right;
            fix.Click+=delegate{Run("Install");};undo.Click+=delegate{Run("Undo");};
            changes=LabelAt(this,"",24,510,652,47,10.5f,FontStyle.Regular);changes.ForeColor=muted;
            check=LinkAt(this,"",24,571,211,28);check.TabIndex=3;check.LinkClicked+=delegate{Run("Check");};
            details=LinkAt(this,"",247,571,165,28);details.TabIndex=4;details.LinkClicked+=delegate{ShowDetails();};
            help=LinkAt(this,"",476,571,200,28);help.Anchor=AnchorStyles.Top|AnchorStyles.Right;help.TabIndex=5;help.LinkClicked+=delegate{ShowHelp();};
            compatibility=LabelAt(this,"",24,616,652,35,9,FontStyle.Regular);compatibility.ForeColor=muted;
            language.SelectedIndex=System.Globalization.CultureInfo.InstalledUICulture.TwoLetterISOLanguageName=="ru"?1:0;
            language.SelectedIndexChanged+=delegate{Localize();};
            Localize();
            timer=new System.Windows.Forms.Timer{Interval=100};timer.Tick+=delegate{Poll();};timer.Start();
            FormClosing+=delegate(object sender,FormClosingEventArgs e){
                if(busy){e.Cancel=true;closeRequested=true;elapsed.Text=T("Please wait for this step to finish before closing.","Дождитесь завершения текущего шага перед закрытием.");}
            };
            FormClosed+=delegate{timer.Stop();timer.Dispose();if(worker!=null)worker.Dispose();};
            Resize+=delegate{LayoutButtons();};
            LayoutButtons();
        }
        Label LabelAt(Control parent,string text,int x,int y,int w,int h,float size,FontStyle style){
            var label=new Label{Text=text,Location=new Point(x,y),Size=new Size(w,h),Font=new Font("Segoe UI",size,style),Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,AutoEllipsis=false,UseMnemonic=false};
            parent.Controls.Add(label);return label;
        }
        Button ButtonAt(Control parent,string text,int x,int y,int w,int h,bool primary){
            var button=new Button{Text=text,Location=new Point(x,y),Size=new Size(w,h),FlatStyle=FlatStyle.Flat,Font=new Font("Segoe UI",11,FontStyle.Bold),Cursor=Cursors.Hand,BackColor=primary?blue:Color.White,ForeColor=primary?Color.White:ink};
            button.FlatAppearance.BorderColor=primary?blue:Color.FromArgb(209,217,230);button.FlatAppearance.BorderSize=1;
            parent.Controls.Add(button);return button;
        }
        LinkLabel LinkAt(Control parent,string text,int x,int y,int w,int h){
            var link=new LinkLabel{Text=text,Location=new Point(x,y),Size=new Size(w,h),LinkColor=blue,ActiveLinkColor=blue,LinkBehavior=LinkBehavior.HoverUnderline};
            parent.Controls.Add(link);return link;
        }
        void LayoutButtons(){
            if(card==null||fix==null)return;
            int available=card.ClientSize.Width-64;
            int primary=(int)(available*.59);
            fix.Width=primary;undo.Left=24+primary+16;undo.Width=available-primary;
        }
        bool HasBackup(){
            try{
                string folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ScamVoiceFix");
                return Directory.Exists(folder)&&Directory.GetDirectories(folder,"25996926-*").Any(p=>File.Exists(Path.Combine(p,"state.json")));
            }catch{return false;}
        }
        void Localize(){
            headline.Text=T("Smooth Russian voices","Плавная русская озвучка");
            subtitle.Text=T("One local fix. Play through Steam as usual.","Локальное исправление. Запускайте игру через Steam как обычно.");
            fix.Text=T("Fix voice","Исправить озвучку");undo.Text=T("Undo changes","Отменить изменения");
            check.Text=T("Check compatibility only","Проверить совместимость");
            details.Text=T("Details / copy log","Подробности / журнал");
            help.Text=T("How it works","Как это работает");
            changes.Text=T("Creates a backup, enables Qwen for non-English voices and sets a 60 FPS cap.","Создаёт резервную копию, включает Qwen для иностранных языков и ограничивает игру до 60 FPS.");
            compatibility.Text=T("Unofficial helper  ·  Steam build 25996926  ·  NVIDIA 8 GB+  ·  16 GB system RAM", "Неофициальный помощник  ·  Сборка Steam 25996926  ·  NVIDIA от 8 ГБ  ·  ОЗУ 16 ГБ");
            undo.Enabled=HasBackup();
            RenderIdle();
        }
        void RenderIdle(){
            progress.Visible=false;elapsed.Text="";stage.Text="";statusTitle.ForeColor=ink;
            if(lastOutcome=="Installed"){
                statusTitle.Text=T("Ready to play","Можно играть");statusTitle.ForeColor=green;
                message.Text=T("The fix is installed. Start the game through Steam, select Russian call language and try two NPC replies.","Исправление установлено. Запустите игру через Steam, выберите русский язык звонков и проверьте два ответа персонажей.");
            }else if(lastOutcome=="Restored"){
                statusTitle.Text=T("Original settings restored","Исходные настройки восстановлены");statusTitle.ForeColor=green;
                message.Text=T("The original game file and your previous Qwen and FPS settings are restored. You can start the game through Steam.","Исходный файл игры и прежние настройки Qwen и FPS восстановлены. Можно запустить игру через Steam.");
            }else if(lastOutcome=="AlreadyFixed"){
                statusTitle.Text=T("This PC is already fixed","На этом ПК исправление уже есть");statusTitle.ForeColor=green;
                message.Text=T("The tested patch is already installed. Keep using your existing backup and undo instructions. No changes were made.","Проверенный патч уже установлен. Используйте прежнюю резервную копию и инструкцию по отмене. Изменений нет.");
            }else if(lastOutcome=="Checked"){
                statusTitle.Text=T("Compatibility checks passed","Проверка совместимости пройдена");statusTitle.ForeColor=green;
                message.Text=T("The game version, hardware and voice files match. Close the game, then click Fix voice to prepare the cache and apply the fix. This check made no changes.","Версия игры, оборудование и файлы озвучки подходят. Закройте игру и нажмите «Исправить озвучку» для подготовки кэша и установки. Проверка ничего не изменила.");
            }else if(lastOutcome=="Error"){
                statusTitle.Text=T("Could not finish","Не удалось завершить");statusTitle.ForeColor=amber;
                message.Text=lastMessage;
            }else{
                statusTitle.Text=T("Ready when you are","Всё готово к началу");
                message.Text=T("Close Scam With Your Friends, then click Fix voice. We will check your setup, prepare the speech cache and apply the tested fix.\r\n\r\nThe first preparation can take a few minutes.","Закройте Scam With Your Friends и нажмите «Исправить озвучку». Мы проверим совместимость, подготовим кэш озвучки и применим проверенное исправление.\r\n\r\nПервая подготовка может занять несколько минут.");
            }
            stage.Text=undo.Enabled?T("Backup available. Undo is ready.","Резервная копия есть. Изменения можно отменить."):T("A backup will be saved before applying changes.","Перед изменениями будет сохранена резервная копия.");
            if(lastOutcome=="Error")stage.Text=T("Open Details to copy the message for help.","Откройте «Подробности», чтобы скопировать сообщение для помощи.");
        }
        static string Quote(string value){return "\""+value+"\"";}
        void Run(string requestedAction){
            if(busy)return;
            action=requestedAction;lastOutcome="";lastMessage="";currentStage="Checking";completed=false;closeRequested=false;
            log.Clear();string discard;while(lines.TryDequeue(out discard)){}
            try{
                string lang=Ru?"RU":"EN";
                string script=Path.Combine(root,"engine",lang,"files","Fix.ps1");
                if(!File.Exists(script))throw new Exception(T("Files are missing. Extract the entire ZIP again, then launch START.","Не хватает файлов. Заново распакуйте весь ZIP-архив и запустите START."));
                string run=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ScamVoiceFix","UI","Runs",Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(run);resultPath=Path.Combine(run,"result.json");
                var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe"));
                info.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File "+Quote(script)+" -Action "+action+" -ResultPath "+Quote(resultPath);
                info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
                info.StandardOutputEncoding=new UTF8Encoding(false);info.StandardErrorEncoding=new UTF8Encoding(false);
                worker=new Process{StartInfo=info};
                worker.OutputDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)lines.Enqueue(e.Data);};
                worker.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)lines.Enqueue(e.Data);};
                busy=true;fix.Enabled=false;undo.Enabled=false;language.Enabled=false;check.Enabled=false;help.Enabled=false;
                fix.BackColor=Color.FromArgb(218,225,237);fix.ForeColor=muted;
                statusTitle.ForeColor=ink;progress.Visible=true;
                clock=Stopwatch.StartNew();SetStage("Checking");
                worker.Start();worker.BeginOutputReadLine();worker.BeginErrorReadLine();
            }catch(Exception e){
                busy=false;lastOutcome="Error";lastMessage=e.Message;
                log.AppendLine(e.ToString());ResetControls();RenderIdle();
                if(worker!=null){worker.Dispose();worker=null;}
            }
        }
        void SetStage(string value){
            currentStage=value;
            if(value=="Preparing"){
                statusTitle.Text=T("Preparing the voices","Подготовка озвучки");
                message.Text=T("Qwen is preparing its GPU cache. This first run may take a few minutes. Keep the game closed.","Qwen подготавливает кэш видеокарты. Первый запуск может занять несколько минут. Не запускайте игру.");
                stage.Text=T("Step 2 of 4 · Preparing speech","Шаг 2 из 4 · Подготовка озвучки");
            }else if(value=="Testing"){
                statusTitle.Text=T("Checking speech speed","Проверка скорости озвучки");
                message.Text=T("Starting a fresh speech worker to check that voices are fast enough before applying the fix.","Заново запускаем движок озвучки, чтобы проверить его скорость перед применением исправления.");
                stage.Text=T("Step 3 of 4 · Testing speech","Шаг 3 из 4 · Проверка озвучки");
            }else if(value=="Applying"){
                statusTitle.Text=T("Saving your backup and applying the fix","Сохранение копии и установка");
                message.Text=T("The original game file and settings are being saved. Please leave this window open until the step finishes.","Сохраняем исходный файл игры и настройки. Дождитесь завершения этого шага, не закрывая окно.");
                stage.Text=T("Step 4 of 4 · Applying changes","Шаг 4 из 4 · Применение изменений");
            }else if(value=="Restoring"){
                statusTitle.Text=T("Restoring the original setup","Восстановление исходных настроек");
                message.Text=T("Restoring your saved game file and Qwen/FPS settings. Please wait for this step to finish.","Восстанавливаем сохранённый файл игры и настройки Qwen/FPS. Дождитесь завершения этого шага.");
                stage.Text=T("Restoring backup","Восстановление резервной копии");
            }else{
                statusTitle.Text=T("Checking your setup","Проверка совместимости");
                message.Text=T("Finding the game and checking its version, NVIDIA graphics and voice files. If asked, select your game folder.","Ищем игру и проверяем её версию, видеокарту NVIDIA и файлы озвучки. Если появится запрос, выберите папку игры.");
                stage.Text=action=="Install"?T("Step 1 of 4 · Checking compatibility","Шаг 1 из 4 · Проверка совместимости"):T("Checking files","Проверка файлов");
            }
        }
        void Poll(){
            string line;
            while(lines.TryDequeue(out line)){
                if(line.StartsWith("@@VOICEFIX:")){SetStage(line.Substring(11));continue;}
                log.AppendLine(line);
            }
            if(!busy||worker==null)return;
            elapsed.Text=(closeRequested?T("Please wait before closing. Elapsed: ","Дождитесь завершения перед закрытием. Прошло: "):T("Elapsed: ","Прошло: "))+clock.Elapsed.ToString(@"m\:ss");
            if(!worker.HasExited||completed)return;
            completed=true;worker.WaitForExit();
            while(lines.TryDequeue(out line)){if(!line.StartsWith("@@VOICEFIX:"))log.AppendLine(line);}
            try{
                if(!File.Exists(resultPath))throw new Exception(T("The helper stopped before returning a result. Open Details and copy the log for help.","Помощник завершился без результата. Откройте «Подробности» и скопируйте журнал для помощи."));
                var result=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(resultPath));
                lastOutcome=Convert.ToString(result["Outcome"]);lastMessage=Convert.ToString(result["Message"]);
                if(worker.ExitCode!=0&&lastOutcome!="Error")lastOutcome="Error";
                if(lastOutcome=="Error"&&String.IsNullOrWhiteSpace(lastMessage))lastMessage=T("Something interrupted the operation. Open Details to see the log.","Выполнение прервалось. Подробности доступны в журнале.");
                File.WriteAllText(Path.Combine(Path.GetDirectoryName(resultPath),"ui-log.txt"),log.ToString(),new UTF8Encoding(true));
            }catch(Exception e){lastOutcome="Error";lastMessage=e.Message;log.AppendLine(e.ToString());}
            worker.Dispose();worker=null;busy=false;clock.Stop();ResetControls();RenderIdle();
        }
        void ResetControls(){
            fix.Enabled=true;fix.BackColor=blue;fix.ForeColor=Color.White;
            undo.Enabled=HasBackup();language.Enabled=true;check.Enabled=true;help.Enabled=true;progress.Visible=false;
        }
        void ShowDetails(){
            var dialog=new Form{Text=T("Voice fix details","Подробности исправления"),StartPosition=FormStartPosition.CenterParent,Size=new Size(760,520),MinimumSize=new Size(540,380),Font=Font,BackColor=BackColor,MinimizeBox=false};
            var box=new TextBox{Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,WordWrap=false,Dock=DockStyle.Fill,Font=new Font("Consolas",9.5f),Text=log.Length==0?T("No operation has run yet.","Операции ещё не выполнялись."):log.ToString()};
            var bottom=new FlowLayoutPanel{Dock=DockStyle.Bottom,Height=58,Padding=new Padding(12,10,12,8),FlowDirection=FlowDirection.RightToLeft};
            var close=new Button{Text=T("Close","Закрыть"),Width=110,Height=32};close.Click+=delegate{dialog.Close();};
            var copy=new Button{Text=T("Copy details","Скопировать"),Width=155,Height=32};copy.Click+=delegate{try{Clipboard.SetText(box.Text);copy.Text=T("Copied","Скопировано");}catch{copy.Text=T("Try again","Повторите");}};
            bottom.Controls.Add(close);bottom.Controls.Add(copy);dialog.Controls.Add(box);dialog.Controls.Add(bottom);
            dialog.ShowDialog(this);dialog.Dispose();
        }
        void ShowHelp(){
            string text=T(
                "Close the game and click Fix voice. The helper checks compatibility, prepares Qwen's local cache, measures speech speed and saves a backup before applying the fix.\r\n\r\nIt enables Qwen for non-English voices and sets a 60 FPS game cap. Start normally through Steam afterward and test two replies.\r\n\r\nUndo changes restores the original game file and your previous settings. It becomes available after this installer saves a backup.\r\n\r\nRequires the supported Steam build 25996926, NVIDIA graphics with at least 8 GB VRAM, about 16 GB RAM and 6 GB free RAM. Other versions and hardware need separate testing.\r\n\r\nEach affected player needs the fix on their own PC. Steam updates may replace the patch. A driver update or cache cleanup may require running Fix voice again.\r\n\r\nNo account or API key is needed. Source scripts and detailed instructions are in files/engine/EN.",
                "Закройте игру и нажмите «Исправить озвучку». Помощник проверит совместимость, подготовит локальный кэш Qwen, измерит скорость и сохранит резервную копию перед установкой.\r\n\r\nОн включает Qwen для иностранных языков и ограничивает игру до 60 FPS. После установки запустите игру через Steam и проверьте два ответа.\r\n\r\nКнопка «Отменить изменения» восстанавливает исходный файл игры и прежние настройки. Она доступна после создания резервной копии этим установщиком.\r\n\r\nНужны сборка Steam 25996926, NVIDIA с минимум 8 ГБ видеопамяти, около 16 ГБ ОЗУ и 6 ГБ свободной ОЗУ. Другие версии и оборудование требуют отдельной проверки.\r\n\r\nКаждому игроку с проблемой нужно исправление на своём ПК. Обновления Steam могут заменить патч. После обновления драйвера или очистки кэша может понадобиться повторная подготовка.\r\n\r\nАккаунт и API-ключ не нужны. Исходные скрипты и подробная инструкция находятся в files/engine/RU.");
            MessageBox.Show(this,text,T("How it works","Как это работает"),MessageBoxButtons.OK,MessageBoxIcon.Information);
        }
        public static void RunApp(string root){Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new VoiceForm(root));}
    }
}
