import {
  BASE_ATTRI_TYPE_NAMES,
  BaseAttriTypeName,
  CUSTOM_TALENT_CONDITION_TYPES,
  CUSTOM_TALENT_PACK_VERSION,
  CustomTalentCondition,
  CustomTalentConditionType,
  CustomTalentDefinition,
  CustomTalentEffect,
  CustomTalentPack,
  DEFAULT_CUSTOM_TALENT_DURATION_DAYS,
  HERO_SPE_ADD_DATA_TYPE_NAMES,
  HeroSpeAddDataTypeName
} from '../shared/types';

export const BASE_ATTRI_TYPE_LABELS: Record<BaseAttriTypeName, string> = {
  Str: '体魄',
  Agl: '身法',
  Inte: '智力',
  Wil: '意志',
  Con: '根骨',
  Mag: '魅力',
  Internal: '内功',
  Dodge: '轻功',
  Unique: '绝学',
  Fist: '拳掌',
  Sword: '剑法',
  Knife: '刀法',
  Long: '长兵',
  Strange: '奇门',
  Shoot: '射术',
  Med: '医术',
  Poison: '毒术',
  Knowledge: '学识',
  Speech: '口才',
  DigAndCut: '采掘',
  Plant: '采药',
  CraftEquip: '锻造',
  CraftMed: '制药',
  CraftFood: '烹饪'
};

export const CUSTOM_TALENT_CONDITION_TYPE_LABELS: Record<CustomTalentConditionType, string> = {
  stat_min: '玩家属性达到门槛',
  team_stat_sum_min: '队伍属性总和达到门槛'
};

const ATTRIBUTE_EFFECT_LABELS = ['体魄', '身法', '智力', '意志', '根骨', '魅力'];
const COMBAT_SKILL_EFFECT_LABELS = ['内功', '轻功', '绝学', '拳掌', '剑法', '刀法', '长兵', '奇门', '射术'];
const LIVING_SKILL_EFFECT_LABELS = ['医术', '毒术', '学识', '口才', '采掘', '采药', '锻造', '制药', '烹饪'];

const EFFECT_TOKEN_LABELS: Record<string, string> = {
  acc: '命中', add: '增加', all: '全部', anti: '抵抗', armor: '护甲', attri: '属性', attck: '攻击',
  back: '反弹', bad: '恶名', bleed: '流血', block: '格挡', book: '书籍', building: '建筑', burn: '灼烧',
  change: '改变', chest: '胸部', clear: '清空', close: '近战', combo: '连击', confusion: '混乱', contribution: '贡献', counter: '反击',
  crazy: '狂乱', crit: '暴击', cure: '治疗', damage: '伤害', deal: '交易', death: '濒死', defence: '防御', debuff: '负面状态',
  elec: '感电', equip: '装备', equipment: '装备', evade: '闪避', exp: '经验', external: '外功', fame: '名望', far: '远程',
  favor: '好感', fight: '战斗', foot: '足部', force: '强制', frozen: '冻结', gain: '获取', hand: '手部', head: '头部', hit: '命中',
  horse: '坐骑', hp: '生命', internal: '内功', invincible: '无敌', kill: '削减', living: '生活', lose: '失去', mana: '内力',
  max: '上限', med: '医术', minus: '削减', move: '移动', part: '部位', per: '每', point: '点数', poison: '中毒',
  posture: '架势', power: '威力', price: '价格', range: '范围', rate: '比例', reborn: '复活', rebound: '反弹', recover: '恢复', recive: '受到',
  reduce: '降低', resist: '抗性', round: '回合', self: '自身', shield: '护盾', skill: '技能', speed: '速度', stop: '停止',
  stun: '眩晕', suck: '吸取', summon: '召唤物', target: '目标', through: '穿透', travel: '旅行', true: '真实', weight: '重量', wound: '伤势'
};

function indexedEffectLabel(value: HeroSpeAddDataTypeName): string | null {
  const patterns: Array<[RegExp, string[], string]> = [
    [/^attri(\d)$/, ATTRIBUTE_EFFECT_LABELS, '基础属性'],
    [/^addAttri(\d)$/, ATTRIBUTE_EFFECT_LABELS, '增加'],
    [/^reduceAttri(\d)$/, ATTRIBUTE_EFFECT_LABELS, '降低'],
    [/^maxAttri(\d)$/, ATTRIBUTE_EFFECT_LABELS, '基础属性上限'],
    [/^fightSkill(\d)$/, COMBAT_SKILL_EFFECT_LABELS, '战斗技能'],
    [/^fightSkillPower(\d)$/, COMBAT_SKILL_EFFECT_LABELS, '战斗技能威力'],
    [/^maxFightSkill(\d)$/, COMBAT_SKILL_EFFECT_LABELS, '战斗技能上限'],
    [/^fightSkill(\d)ExpRate$/, COMBAT_SKILL_EFFECT_LABELS, '战斗技能经验比例'],
    [/^fightSkillRange(\d)$/, COMBAT_SKILL_EFFECT_LABELS, '战斗技能范围'],
    [/^livingSkill(\d)$/, LIVING_SKILL_EFFECT_LABELS, '生活技能'],
    [/^maxLivingSkill(\d)$/, LIVING_SKILL_EFFECT_LABELS, '生活技能上限'],
    [/^livingSkill(\d)ExpRate$/, LIVING_SKILL_EFFECT_LABELS, '生活技能经验比例'],
    [/^recoverPartPosture(\d)$/, ['头部', '胸部', '背部', '手部', '足部', '全身'], '恢复部位架势']
  ];

  for (const [pattern, labels, prefix] of patterns) {
    const match = value.match(pattern);
    if (match) {
      return `${prefix}：${labels[Number(match[1])] ?? '其他'}`;
    }
  }
  return null;
}

function buildHeroSpeAddDataTypeLabel(value: HeroSpeAddDataTypeName): string {
  const indexed = indexedEffectLabel(value);
  if (indexed) {
    return `${indexed}（${value}）`;
  }

  const tokens = value
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .split(/(?=\d)|\s+/)
    .filter(Boolean)
    .map((token) => EFFECT_TOKEN_LABELS[token.toLowerCase()] ?? '特殊');
  return `效果：${tokens.join('')}（${value}）`;
}

export const HERO_SPE_ADD_DATA_TYPE_LABELS: Record<HeroSpeAddDataTypeName, string> = Object.fromEntries(
  HERO_SPE_ADD_DATA_TYPE_NAMES.map((value) => [value, buildHeroSpeAddDataTypeLabel(value)])
) as Record<HeroSpeAddDataTypeName, string>;

function createId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }

  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
}

export function createEmptyCustomTalentPack(): CustomTalentPack {
  return {
    version: CUSTOM_TALENT_PACK_VERSION,
    talents: []
  };
}

export function createCustomTalentCondition(): CustomTalentCondition {
  return {
    type: 'stat_min',
    stat: 'Inte',
    min: 10
  };
}

export function createCustomTalentEffect(): CustomTalentEffect {
  return {
    effectType: 'addAttri2',
    value: 10
  };
}

export function createCustomTalent(name = '新天赋'): CustomTalentDefinition {
  return {
    id: createId('custom-talent'),
    enabled: true,
    name,
    durationDays: DEFAULT_CUSTOM_TALENT_DURATION_DAYS,
    conditions: [createCustomTalentCondition()],
    effects: [createCustomTalentEffect()]
  };
}

export function cloneCustomTalentPack(pack: CustomTalentPack): CustomTalentPack {
  return {
    version: CUSTOM_TALENT_PACK_VERSION,
    talents: pack.talents.map((talent) => ({
      id: talent.id,
      enabled: talent.enabled,
      name: talent.name,
      durationDays: talent.durationDays,
      conditions: talent.conditions.map((condition) => ({
        type: condition.type,
        stat: condition.stat,
        min: condition.min
      })),
      effects: talent.effects.map((effect) => ({
        effectType: effect.effectType,
        value: effect.value
      }))
    }))
  };
}

export function duplicateCustomTalent(talent: CustomTalentDefinition): CustomTalentDefinition {
  return {
    ...cloneCustomTalentPack({ version: CUSTOM_TALENT_PACK_VERSION, talents: [talent] }).talents[0],
    id: createId('custom-talent'),
    name: `${talent.name.trim() || '新天赋'} 副本`
  };
}

export function validateCustomTalentPack(pack: CustomTalentPack): string[] {
  const errors: string[] = [];
  const seenNames = new Set<string>();

  if (pack.version !== CUSTOM_TALENT_PACK_VERSION) {
    errors.push(`配置版本必须是 ${CUSTOM_TALENT_PACK_VERSION}。`);
  }

  pack.talents.forEach((talent, talentIndex) => {
    const displayIndex = talentIndex + 1;
    const trimmedName = talent.name.trim();
    if (!trimmedName) {
      errors.push(`第 ${displayIndex} 个天赋名称不能为空。`);
    }
    else if (seenNames.has(trimmedName)) {
      errors.push(`天赋名称不能重复：${trimmedName}`);
    }
    else {
      seenNames.add(trimmedName);
    }

    if (!Number.isInteger(talent.durationDays) || talent.durationDays < 1) {
      errors.push(`第 ${displayIndex} 个天赋的持续天数必须是大于等于 1 的整数。`);
    }

    if (talent.conditions.length === 0) {
      errors.push(`第 ${displayIndex} 个天赋至少需要 1 条条件。`);
    }

    if (talent.effects.length === 0) {
      errors.push(`第 ${displayIndex} 个天赋至少需要 1 条效果。`);
    }

    talent.conditions.forEach((condition, conditionIndex) => {
      if (!(CUSTOM_TALENT_CONDITION_TYPES as readonly string[]).includes(condition.type)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件类型无效。`);
      }
      if (!(BASE_ATTRI_TYPE_NAMES as readonly string[]).includes(condition.stat)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件属性无效。`);
      }
      if (!Number.isFinite(condition.min)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件最低值无效。`);
      }
    });

    talent.effects.forEach((effect, effectIndex) => {
      if (!(HERO_SPE_ADD_DATA_TYPE_NAMES as readonly string[]).includes(effect.effectType)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${effectIndex + 1} 条效果类型无效。`);
      }
      if (!Number.isFinite(effect.value)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${effectIndex + 1} 条效果数值无效。`);
      }
    });
  });

  return errors;
}

export function formatBaseAttriType(value: BaseAttriTypeName): string {
  return BASE_ATTRI_TYPE_LABELS[value] ?? value;
}

export function formatCustomTalentConditionType(value: CustomTalentConditionType): string {
  return CUSTOM_TALENT_CONDITION_TYPE_LABELS[value] ?? value;
}

export function formatHeroSpeAddDataType(value: HeroSpeAddDataTypeName): string {
  return HERO_SPE_ADD_DATA_TYPE_LABELS[value];
}
