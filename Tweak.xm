#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <math.h>

// ---------------------------------------------------------------- offsets
// Re-verify every game patch.
#define CLS_PLAYER        "Player"
#define CLS_PLAYERMGR     "PlayerManager"
#define CLS_COMPONENT     "Component"
#define CLS_TRANSFORM     "Transform"
#define CLS_CAMERA        "Camera"
#define CLS_QUATERNION    "Quaternion"

#define FLD_ALLPLAYERS    "allPlayers"
#define FLD_LOCALPLAYER   "localPlayer"
#define FLD_HEALTH        "health"
#define FLD_TEAM          "team"
#define FLD_HEAD          "headTransform"
#define FLD_ISFIRING      "isFiring"
#define FLD_SKIN          "currentSkinId"
#define FLD_SHAKE         "shakeIntensity"

#define MTH_W2S           "WorldToScreenPoint"
#define MTH_CAMMAIN       "get_main"
#define MTH_GETPOS        "get_position"
#define MTH_GETROT        "get_rotation"
#define MTH_SETROT        "set_rotation"
#define MTH_GETTRANSFORM  "get_transform"
#define MTH_LOOKROT       "LookRotation"
#define MTH_APPLYSKIN     "ApplySkin"

#define LIST_ITEMS 0x10
#define LIST_SIZE  0x18

typedef struct { float x, y, z; } V3;
typedef struct { float x, y, z, w; } Quat;

typedef void Il2CppClass, Il2CppMethod, Il2CppField, Il2CppImage,
             Il2CppAssembly, Il2CppDomain, Il2CppObject, Il2CppExc;

static Il2CppDomain* (*p_dom)(void);
static const Il2CppAssembly** (*p_asms)(Il2CppDomain*, size_t*);
static Il2CppImage* (*p_img)(const Il2CppAssembly*);
static Il2CppClass* (*p_cls)(const Il2CppImage*, const char*, const char*);
static Il2CppField* (*p_fld)(Il2CppClass*, const char*);
static void (*p_fget)(void*, Il2CppField*, void*);
static void (*p_fset)(void*, Il2CppField*, void*);
static void (*p_fsget)(Il2CppField*, void*);
static Il2CppMethod* (*p_mth)(Il2CppClass*, const char*, int);
static void* (*p_inv)(Il2CppMethod*, void*, void**, Il2CppExc**);

static Il2CppClass *kPlayer, *kMgr, *kComp, *kTrans, *kCam, *kQuat;
static Il2CppField *fList, *fLocal, *fHp, *fTeam, *fHead, *fFire, *fSkin, *fShake;
static Il2CppMethod *mW2S, *mCamMain, *mGetPos, *mGetRot, *mSetRot, *mGetTrans, *mLook, *mSkin;

// ---------------------------------------------------------------- config
typedef struct {
    BOOL master, espBox, espLine, espName, radar,
         aimbot, aimOnlyFiring, noShake, skinOn;
    float fov;
    float smooth;
    int bone;
    int skinId;
} CO_Config;

static CO_Config gCfg;

// ---------------------------------------------------------------- esp
@interface COESPView : UIView
@property (nonatomic) NSArray *boxes;
@property (nonatomic) NSArray *lines;
@property (nonatomic) NSArray *names;
@property (nonatomic) NSArray *dots;
@end

static COESPView *gView;
static NSMutableArray *bBoxes, *bLines, *bNames, *bDots;

static CGPoint ESPCenter(void) {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGPointMake(s.width / 2, s.height / 2);
}

@implementation COESPView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.opaque = NO;
    }
    return self;
}
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(c, 1.4);
    CGContextSetStrokeColorWithColor(c, UIColor.greenColor.CGColor);
    for (NSValue *v in self.boxes) { CGRect b; [v getValue:&b]; CGContextStrokeRect(c, b); }
    for (NSValue *v in self.lines) {
        CGPoint p; [v getValue:&p];
        CGContextMoveToPoint(c, p.x, p.y);
        CGContextAddLineToPoint(c, ESPCenter().x, self.bounds.size.height - 20);
        CGContextStrokePath(c);
    }
    NSDictionary *at = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:10],
                          NSForegroundColorAttributeName: UIColor.greenColor };
    for (NSArray *pair in self.names)
        [pair[1] drawAtPoint:[pair[0] CGPointValue] withAttributes:at];
    CGContextSetFillColorWithColor(c, UIColor.greenColor.CGColor);
    for (NSValue *v in self.dots) {
        CGPoint p; [v getValue:&p];
        CGContextFillEllipseInRect(c, CGRectMake(p.x - 2.5, p.y - 2.5, 5, 5));
    }
}
@end

static void ESPAttach(void) {
    bBoxes = [NSMutableArray new]; bLines = [NSMutableArray new];
    bNames = [NSMutableArray new]; bDots = [NSMutableArray new];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = UIApplication.sharedApplication.keyWindow;
        if (!w) return;
        gView = [[COESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        gView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [w addSubview:gView];
        CADisplayLink *l = [CADisplayLink displayLinkWithTarget:gView selector:@selector(setNeedsDisplay)];
        [l addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    });
}

static void ESPBegin(void) {
    [bBoxes removeAllObjects]; [bLines removeAllObjects];
    [bNames removeAllObjects]; [bDots removeAllObjects];
}
static void ESPBox(CGPoint h, CGPoint f) {
    CGFloat ht = f.y - h.y;
    CGFloat wd = ht * 0.42;
    [bBoxes addObject:[NSValue valueWithCGRect:CGRectMake(h.x - wd / 2, h.y, wd, ht)]];
}
static void ESPLine(CGPoint h, CGPoint f) {
    [bLines addObject:[NSValue valueWithCGPoint:CGPointMake((h.x + f.x) / 2, f.y)]];
}
static void ESPName(CGPoint h, NSString *n) {
    [bNames addObject:@[ [NSValue valueWithCGPoint:CGPointMake(h.x, h.y - 12)], n ]];
}
static void ESPDot(CGPoint p) { [bDots addObject:[NSValue valueWithCGPoint:p]]; }
static void ESPEnd(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gView.boxes = bBoxes.copy; gView.lines = bLines.copy;
        gView.names = bNames.copy; gView.dots = bDots.copy;
    });
}

// ---------------------------------------------------------------- menu
@interface COFab : UIButton
@end
static UIView *gPanel;
static BOOL gOpen;

static void saveCfg(void) {
    [NSUserDefaults.standardUserDefaults setObject:[NSData dataWithBytes:&gCfg length:sizeof(CO_Config)]
                                           forKey:@"co_cfg"];
}
static void loadCfg(void) {
    NSData *n = [NSUserDefaults.standardUserDefaults objectForKey:@"co_cfg"];
    if (n.length == sizeof(CO_Config)) [n getBytes:&gCfg length:sizeof(CO_Config)];
    else { gCfg.fov = 120; gCfg.smooth = 8; gCfg.bone = 0; gCfg.skinId = 0; }
}

@implementation COFab
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self
                                          action:@selector(pan:)]];
    }
    return self;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

static UILabel *rowLabel(NSString *t) {
    UILabel *l = [UILabel new];
    l.text = t;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    return l;
}
static void addToggle(UIStackView *st, NSString *title, BOOL *bind) {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    [row addArrangedSubview:rowLabel(title)];
    UISwitch *s = [UISwitch new];
    s.onTintColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    s.transform = CGAffineTransformMakeScale(0.72, 0.72);
    s.on = *bind;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { *bind = s.on; saveCfg(); }]
     forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:s];
    [st addArrangedSubview:row];
}
static void addSlider(UIStackView *st, NSString *title, float lo, float hi, float *bind) {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisVertical;
    UILabel *l = rowLabel([NSString stringWithFormat:@"%@ %.0f", title, *bind]);
    UISlider *s = [UISlider new];
    s.minimumValue = lo; s.maximumValue = hi; s.value = *bind;
    s.tintColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    __weak UILabel *wl = l;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) {
        *bind = s.value;
        wl.text = [NSString stringWithFormat:@"%@ %.0f", title, s.value];
        saveCfg();
    }] forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:l];
    [row addArrangedSubview:s];
    [st addArrangedSubview:row];
}
static void addSkinRow(UIStackView *st) {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    [row addArrangedSubview:rowLabel(@"Skin ID")];
    UITextField *tf = [UITextField new];
    tf.text = [NSString stringWithFormat:@"%d", gCfg.skinId];
    tf.textColor = UIColor.whiteColor;
    tf.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.keyboardType = UIKeyboardTypeNumberPad;
    [tf.widthAnchor constraintEqualToConstant:70].active = YES;
    [tf addAction:[UIAction actionWithHandler:^(UIAction *a) {
        gCfg.skinId = tf.text.intValue;
        saveCfg();
    }] forControlEvents:UIControlEventEditingDidEnd];
    [row addArrangedSubview:tf];
    [st addArrangedSubview:row];
}

static UIView *buildPanel(void) {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 210, 390)];
    p.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.95];
    p.layer.cornerRadius = 12;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;

    UILabel *title = rowLabel(@"C-OPS  venice");
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 8, 210, 20);
    [p addSubview:title];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 34, 210, 350)];
    [p addSubview:sv];

    UIStackView *st = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 210, 0)];
    st.axis = UILayoutConstraintAxisVertical;
    st.spacing = 6;
    [sv addSubview:st];

    addToggle(st, @"Master", &gCfg.master);
    addToggle(st, @"ESP box", &gCfg.espBox);
    addToggle(st, @"ESP line", &gCfg.espLine);
    addToggle(st, @"ESP name", &gCfg.espName);
    addToggle(st, @"Radar", &gCfg.radar);
    addToggle(st, @"Aimbot", &gCfg.aimbot);
    addToggle(st, @"Aim on fire only", &gCfg.aimOnlyFiring);
    addSlider(st, @"FOV", 20, 400, &gCfg.fov);
    addSlider(st, @"Smooth", 1, 20, &gCfg.smooth);
    addToggle(st, @"No camera shake", &gCfg.noShake);
    addToggle(st, @"Skin changer", &gCfg.skinOn);
    addSkinRow(st);

    [st sizeToFit];
    sv.contentSize = st.bounds.size;
    return p;
}

static void COMenuAttach(void) {
    loadCfg();
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (!w) return;

    COFab *fab = [[COFab alloc] initWithFrame:CGRectMake(12, 120, 46, 46)];
    fab.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    fab.layer.cornerRadius = 23;
    fab.layer.borderWidth = 1;
    fab.layer.borderColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1].CGColor;
    [fab setTitle:@"CO" forState:UIControlStateNormal];
    [fab setTitleColor:[UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1]
              forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [fab addAction:[UIAction actionWithHandler:^(UIAction *a) {
        gOpen = !gOpen;
        if (gOpen) {
            gPanel = buildPanel();
            gPanel.center = CGPointMake(120, 270);
            [w addSubview:gPanel];
        } else {
            [gPanel removeFromSuperview];
            gPanel = nil;
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:fab];
}

// ---------------------------------------------------------------- game
static void *S(const char *n) { return dlsym(RTLD_DEFAULT, n); }

static Il2CppClass *FindClass(const char *name) {
    size_t c = 0;
    const Il2CppAssembly **a = p_asms(p_dom(), &c);
    if (!a) return NULL;
    for (size_t i = 0; i < c; i++) {
        Il2CppImage *im = p_img(a[i]);
        if (!im) continue;
        Il2CppClass *k = p_cls(im, "", name);
        if (k) return k;
    }
    return NULL;
}

static BOOL COBoot(void) {
    p_dom  = S("il2cpp_domain_get");
    p_asms = S("il2cpp_domain_get_assemblies");
    p_img  = S("il2cpp_assembly_get_image");
    p_cls  = S("il2cpp_class_from_name");
    p_fld  = S("il2cpp_class_get_field_from_name");
    p_fget = S("il2cpp_field_get_value");
    p_fset = S("il2cpp_field_set_value");
    p_fsget = S("il2cpp_field_static_get_value");
    p_mth  = S("il2cpp_class_get_method_from_name");
    p_inv  = S("il2cpp_runtime_invoke");
    if (!p_dom || !p_cls || !p_inv) return NO;

    kPlayer = FindClass(CLS_PLAYER);
    kMgr    = FindClass(CLS_PLAYERMGR);
    kComp   = FindClass(CLS_COMPONENT);
    kTrans  = FindClass(CLS_TRANSFORM);
    kCam    = FindClass(CLS_CAMERA);
    kQuat   = FindClass(CLS_QUATERNION);
    if (!kPlayer || !kTrans) return NO;

    fList  = kMgr ? p_fld(kMgr, FLD_ALLPLAYERS) : NULL;
    fLocal = p_fld(kPlayer, FLD_LOCALPLAYER);
    fHp    = p_fld(kPlayer, FLD_HEALTH);
    fTeam  = p_fld(kPlayer, FLD_TEAM);
    fHead  = p_fld(kPlayer, FLD_HEAD);
    fFire  = p_fld(kPlayer, FLD_ISFIRING);
    fSkin  = p_fld(kPlayer, FLD_SKIN);
    fShake = p_fld(kPlayer, FLD_SHAKE);
    mSkin  = p_mth(kPlayer, MTH_APPLYSKIN, 0);

    if (kCam) { mW2S = p_mth(kCam, MTH_W2S, 1); mCamMain = p_mth(kCam, MTH_CAMMAIN, 0); }
    mGetPos = p_mth(kTrans, MTH_GETPOS, 0);
    mGetRot = p_mth(kTrans, MTH_GETROT, 0);
    mSetRot = p_mth(kTrans, MTH_SETROT, 1);
    if (kComp) mGetTrans = p_mth(kComp, MTH_GETTRANSFORM, 0);
    if (kQuat) mLook = p_mth(kQuat, MTH_LOOKROT, 1);

    return (mW2S && mCamMain && mGetPos && mGetRot && mSetRot && mGetTrans);
}

static void *Local(void) {
    if (!fLocal) return NULL;
    void *p = NULL;
    p_fsget(fLocal, &p);
    return p;
}

static BOOL Project(V3 w, CGPoint *o) {
    void *cam = p_inv(mCamMain, NULL, NULL, NULL);
    if (!cam) return NO;
    void *args[1] = { &w };
    void *r = p_inv(mW2S, cam, args, NULL);
    if (!r) return NO;
    float *f = (float *)r;
    if (f[2] < 0.2f) return NO;
    o->x = f[0];
    o->y = UIScreen.mainScreen.bounds.size.height - f[1];
    return YES;
}

static BOOL TransPos(void *obj, V3 *out) {
    if (!obj || !mGetTrans || !mGetPos) return NO;
    void *t = p_inv(mGetTrans, obj, NULL, NULL);
    if (!t) return NO;
    void *r = p_inv(mGetPos, t, NULL, NULL);
    if (!r) return NO;
    *out = *(V3 *)r;
    return YES;
}

static void Nlerp(Quat a, Quat b, float t, Quat *o) {
    float d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    if (d < 0) { b.x = -b.x; b.y = -b.y; b.z = -b.z; b.w = -b.w; }
    o->x = a.x + (b.x - a.x) * t;
    o->y = a.y + (b.y - a.y) * t;
    o->z = a.z + (b.z - a.z) * t;
    o->w = a.w + (b.w - a.w) * t;
    float n = sqrtf(o->x * o->x + o->y * o->y + o->z * o->z + o->w * o->w);
    if (n < 0.0001f) { *o = b; return; }
    o->x /= n; o->y /= n; o->z /= n; o->w /= n;
}

static void COApplySkin(int id) {
    void *me = Local();
    if (!me || !fSkin) return;
    int s = id;
    p_fset(me, fSkin, &s);
    if (mSkin) p_inv(mSkin, me, NULL, NULL);
}

static void COTick(void) {
    if (!gCfg.master) { ESPBegin(); ESPEnd(); return; }

    void *me = Local();
    if (!me) return;

    if (gCfg.noShake && fShake) { float z = 0; p_fset(me, fShake, &z); }
    if (gCfg.skinOn && gCfg.skinId > 0) COApplySkin(gCfg.skinId);

    void *list = NULL;
    if (fList) p_fsget(fList, &list);
    int n = 0;
    void **items = NULL;
    if (list) {
        n = *(int *)((uint8_t *)list + LIST_SIZE);
        items = *(void ***)((uint8_t *)list + LIST_ITEMS);
    }
    if (!items) { ESPBegin(); ESPEnd(); return; }

    int myTeam = 0;
    if (fTeam) p_fget(me, fTeam, &myTeam);

    ESPBegin();
    void *best = NULL;
    float bestD = 1e9f;
    CGPoint ctr = ESPCenter();

    for (int i = 0; i < n; i++) {
        void *pl = items[i];
        if (!pl || pl == me) continue;

        int hp = 0;
        if (fHp) p_fget(pl, fHp, &hp);
        if (hp <= 0) continue;

        int tm = 0;
        if (fTeam) p_fget(pl, fTeam, &tm);
        BOOL fr = (tm == myTeam);

        V3 head;
        void *ht = NULL;
        if (fHead) p_fget(pl, fHead, &ht);
        if (ht) { if (!TransPos(ht, &head)) continue; }
        else if (!TransPos(pl, &head)) continue;

        V3 foot = head; foot.y -= 1.65f;

        CGPoint sh, sf;
        if (!Project(head, &sh)) continue;
        if (!Project(foot, &sf)) continue;

        if (gCfg.espBox) ESPBox(sh, sf);
        if (gCfg.espLine) ESPLine(sh, sf);
        if (gCfg.espName) ESPName(sh, fr ? @"TEAM" : @"ENEMY");

        float d = hypotf(sh.x - ctr.x, sh.y - ctr.y);
        if (!fr && d < gCfg.fov && d < bestD) { bestD = d; best = pl; }
    }

    if (gCfg.radar && mGetRot) {
        V3 mp;
        void *mt = p_inv(mGetTrans, me, NULL, NULL);
        if (mt && TransPos(me, &mp)) {
            float yaw = 0;
            void *rr = p_inv(mGetRot, mt, NULL, NULL);
            if (rr) {
                Quat q = *(Quat *)rr;
                yaw = atan2f(2.0f * (q.w * q.y + q.x * q.z),
                             1.0f - 2.0f * (q.y * q.y + q.x * q.x));
            }
            CGSize sc = UIScreen.mainScreen.bounds.size;
            CGPoint rc = CGPointMake(sc.width - 78, 150);
            float sn = sinf(-yaw), cs = cosf(-yaw);
            for (int i = 0; i < n; i++) {
                void *pl = items[i];
                if (!pl || pl == me) continue;
                V3 wp;
                if (!TransPos(pl, &wp)) continue;
                float dx = wp.x - mp.x, dz = wp.z - mp.z;
                CGPoint pt = CGPointMake(rc.x + (dx * cs - dz * sn) * 1.6f,
                                         rc.y + (dx * sn + dz * cs) * 1.6f);
                if (hypotf(pt.x - rc.x, pt.y - rc.y) < 62) ESPDot(pt);
            }
        }
    }

    ESPEnd();

    if (gCfg.aimbot && best) {
        BOOL fire = YES;
        if (gCfg.aimOnlyFiring && fFire) {
            uint8_t b = 0; p_fget(me, fFire, &b); fire = b != 0;
        }
        if (fire) {
            V3 tgt;
            void *th = NULL;
            if (fHead) p_fget(best, fHead, &th);
            BOOL ok = th ? TransPos(th, &tgt) : TransPos(best, &tgt);
            if (ok && gCfg.bone == 1) tgt.y -= 0.35f;

            V3 eye;
            if (ok && TransPos(me, &eye)) {
                V3 dir = { tgt.x - eye.x, tgt.y - eye.y, tgt.z - eye.z };
                float len = sqrtf(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
                if (len > 0.01f) {
                    void *qa = &dir;
                    void *want = p_inv(mLook, NULL, &qa, NULL);
                    void *mt2 = p_inv(mGetTrans, me, NULL, NULL);
                    if (want && mt2) {
                        void *cur = p_inv(mGetRot, mt2, NULL, NULL);
                        Quat out;
                        if (cur) Nlerp(*(Quat *)cur, *(Quat *)want,
                                       1.0f / fmaxf(gCfg.smooth, 1.0f), &out);
                        else out = *(Quat *)want;
                        void *qa2 = &out;
                        p_inv(mSetRot, mt2, &qa2, NULL);
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- entry
static void Boot(void) {
    if (!COBoot()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ Boot(); });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        ESPAttach();
        COMenuAttach();
    });
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                            dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    dispatch_source_set_timer(t, DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC, 4 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t, ^{ COTick(); });
    dispatch_resume(t);
}

%ctor {
    if (![[[NSBundle mainBundle] bundleIdentifier]
            isEqualToString:@"com.criticalforceentertainment.criticalops"]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ Boot(); });
}
